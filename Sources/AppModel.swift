import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: SectionItem = .overview
    @Published var device: DeviceInfo?
    @Published var deviceName = "Подключённый Mac"
    @Published var firmwares: [Firmware] = []
    @Published var selectedFirmware: Firmware?
    @Published var sessionPhase: SessionPhase = .disconnected
    @Published var status = "Готово"
    @Published var detail = "Ожидание подключения"
    @Published var busy = false
    @Published var lastError: String?
    @Published var downloadedPath: String?
    @Published var recoveryProgress: Double = 0
    @Published var selectedRecoveryKind: RecoveryKind = .restore
    @Published var cacheSize: Int64 = 0
    @Published var lastCatalogRefresh: Date?
    @Published var toolStatus: ToolStatus?

    let settings = AppSettings.shared
    let downloads = DownloadManager.shared
    let history = HistoryStore.shared

    private let backend: BackendServing
    private var pendingJob: (kind: RecoveryKind, device: DeviceInfo, firmware: Firmware)?
    private var monitorTask: Task<Void, Never>?

    init(backend: BackendServing = BackendClient()) {
        self.backend = backend
        self.backend.demoMode = settings.demoMode
        downloads.onCompletion = { [weak self] result in
            Task { @MainActor in self?.downloadFinished(result) }
        }
        if downloads.phase == .paused {
            status = "Загрузка приостановлена"
            detail = "Можно продолжить загрузку с сохранённого места"
        }
        updateCacheSize()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            await self.checkToolchain()
            await self.refreshDevice(silent: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !self.busy && !self.downloads.phase.isActive {
                    await self.refreshDevice(silent: true)
                }
            }
        }
    }

    deinit { monitorTask?.cancel() }

    var language: AppLanguage { settings.language }
    var isRecoveryRunning: Bool { sessionPhase == .recovering }
    var cfgutilReady: Bool { toolStatus?.cfgutilInstalled == true }

    func checkToolchain() async {
        do {
            let output = try await backend.run(["capabilities"], onOutput: nil)
            toolStatus = try JSONDecoder().decode(ToolStatus.self, from: Data(output.utf8))
        } catch {
            toolStatus = ToolStatus(
                configuratorInstalled: false,
                configuratorPath: "",
                cfgutilInstalled: false,
                cfgutilPath: ""
            )
        }
    }

    func checkToolchainNow() {
        Task {
            await checkToolchain()
            if cfgutilReady { await refreshDevice(silent: false) }
        }
    }

    func openConfiguratorSetup() {
        if let path = toolStatus?.configuratorPath, !path.isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: configuration,
                completionHandler: nil
            )
            let alert = NSAlert()
            alert.messageText = L10n.text(
                "Установите Automation Tools",
                "Install Automation Tools",
                language
            )
            alert.informativeText = L10n.text(
                "В открывшемся Apple Configurator выберите меню Apple Configurator → Install Automation Tools… и подтвердите пароль администратора. Затем вернитесь сюда и нажмите «Проверить снова».",
                "In Apple Configurator choose Apple Configurator → Install Automation Tools… and approve the administrator prompt. Return here and choose Check Again.",
                language
            )
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } else if let url = URL(string: "macappstore://itunes.apple.com/app/id1037126344") {
            NSWorkspace.shared.open(url)
        }
    }

    func openConfiguratorHelp() {
        if let url = URL(string: "https://support.apple.com/guide/deployment/configure-devices-dep6f70f6647/web") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAppleDFUGuide() {
        if let url = URL(string: "https://support.apple.com/108900") { NSWorkspace.shared.open(url) }
    }

    func openAppleDFUPortGuide() {
        if let url = URL(string: "https://support.apple.com/120694") { NSWorkspace.shared.open(url) }
    }

    func openFinder() {
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        NSWorkspace.shared.openApplication(at: finder, configuration: .init(), completionHandler: nil)
    }

    func refreshDevice(silent: Bool = false) async {
        if !silent {
            status = L10n.text("Поиск устройства", "Detecting device", language)
            sessionPhase = .detecting
        }
        backend.demoMode = settings.demoMode
        do {
            let output = try await backend.run(["detect"], onOutput: nil)
            let found = try JSONDecoder().decode(DeviceInfo.self, from: Data(output.utf8))
            let changed = found != device
            device = found
            sessionPhase = .connected
            status = "DFU Mode"
            detail = L10n.text(
                "Mac обнаружен и готов к безопасной проверке",
                "Mac detected and ready for safety checks",
                language
            )
            if changed || firmwares.isEmpty, settings.automaticCatalogRefresh {
                await loadFirmwares()
            }
        } catch {
            if isRecoveryRunning {
                sessionPhase = .recoveryNeeded
                status = L10n.text("Соединение потеряно", "Connection lost", language)
                detail = L10n.text(
                    "Не отключайте питание. Верните устройство в DFU и повторите Restore.",
                    "Keep power connected. Return the device to DFU and retry Restore.",
                    language
                )
                return
            }
            device = nil
            deviceName = L10n.text("Подключённый Mac", "Connected Mac", language)
            firmwares = []
            selectedFirmware = nil
            sessionPhase = .disconnected
            status = L10n.text("Готово", "Ready", language)
            detail = L10n.text(
                "Подключите Mac и переведите его в DFU",
                "Connect the Mac and place it in DFU",
                language
            )
            if !silent, (error as NSError).code != 6 { lastError = error.localizedDescription }
        }
    }

    func loadFirmwares() async {
        guard let device else { return }
        backend.demoMode = settings.demoMode
        do {
            let source = try firmwareSourceArguments()
            let output = try await backend.run(
                [
                    "firmwares", device.type, source.kind.rawValue, source.value,
                    (settings.includeBetaFirmwares || source.kind == .ipswBeta) ? "1" : "0"
                ],
                onOutput: nil
            )
            let response = try JSONDecoder().decode(FirmwareResponse.self, from: Data(output.utf8))
            deviceName = response.name.isEmpty ? device.type : response.name
            firmwares = (settings.includeBetaFirmwares || source.kind == .ipswBeta)
                ? response.firmwares
                : response.firmwares.filter { !$0.isBeta }
            if let selectedFirmware, firmwares.contains(selectedFirmware) {
                self.selectedFirmware = selectedFirmware
            } else {
                selectedFirmware = firmwares.first
            }
            lastCatalogRefresh = Date()
            status = "DFU Mode"
            detail = L10n.text(
                "Доступно IPSW: \(firmwares.count)",
                "Available IPSW: \(firmwares.count)",
                language
            )
        } catch {
            lastError = error.localizedDescription
            status = L10n.text("Ошибка каталога IPSW", "IPSW catalog error", language)
            detail = error.localizedDescription
        }
    }

    func refreshFirmwares() {
        guard !busy else { return }
        busy = true
        Task {
            await loadFirmwares()
            busy = false
        }
    }

    func enterDFU() {
        guard !busy else { return }
        selection = .dfu
        busy = true
        sessionPhase = .enteringDFU
        status = L10n.text("Отправка команды DFU", "Sending DFU command", language)
        detail = L10n.text(
            "Подключите Target Mac правильным портом и подтвердите пароль администратора.",
            "Connect the target Mac through its correct port and approve the administrator prompt.",
            language
        )
        backend.demoMode = settings.demoMode
        Task {
            do {
                _ = try await backend.run(["dfu"]) { [weak self] chunk in
                    let message = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !message.isEmpty else { return }
                    Task { @MainActor in self?.detail = message }
                }
                await refreshDevice(silent: true)
                guard device != nil else {
                    throw AppError.message(L10n.text(
                        "Команда отправлена, но DFU не подтверждён. Проверьте кабель и DFU-порт.",
                        "The command was sent, but DFU was not confirmed. Check the cable and DFU port.",
                        language
                    ))
                }
                sessionPhase = .connected
                status = "DFU Mode"
                detail = L10n.text("Mac успешно переведён в DFU кнопкой.", "The Mac was placed in DFU by the app.", language)
            } catch {
                sessionPhase = .failed
                status = L10n.text("Автоматический DFU не выполнен", "Automatic DFU failed", language)
                detail = L10n.text(
                    "Проверьте прямое подключение, DFU-порт и кабель. Ниже оставлена ручная последовательность.",
                    "Check the direct connection, DFU port, and cable. The manual sequence is shown below.",
                    language
                )
                lastError = error.localizedDescription
            }
            busy = false
        }
    }

    func checkDFUPresenceNow() {
        guard !busy else { return }
        busy = true
        Task {
            await refreshDevice(silent: false)
            busy = false
        }
    }

    func downloadOnly() {
        guard let firmware = selectedFirmware else { return }
        pendingJob = nil
        guard hasDownloadSpace(for: firmware) else { return }
        sessionPhase = .downloading
        status = L10n.text("Загрузка macOS \(firmware.version)", "Downloading macOS \(firmware.version)", language)
        detail = settings.downloadDirectoryPath
        downloads.start(firmware: firmware, directory: settings.downloadDirectory, demo: settings.demoMode)
        selection = .downloads
    }

    func requestRecovery() {
        guard let device, let firmware = selectedFirmware else { return }
        let kind = RecoveryKind.restore
        selectedRecoveryKind = .restore
        guard confirm(kind: kind, device: device, firmware: firmware) else { return }
        pendingJob = (kind, device, firmware)
        let candidate = localURL(for: firmware)
        if FileManager.default.fileExists(atPath: candidate.path) {
            downloadedPath = candidate.path
            Task { await runRecovery(kind: kind, device: device, firmware: firmware, file: candidate) }
        } else {
            guard hasDownloadSpace(for: firmware) else { pendingJob = nil; return }
            sessionPhase = .downloading
            status = L10n.text("Сначала загружается IPSW", "Downloading IPSW first", language)
            detail = settings.downloadDirectoryPath
            downloads.start(firmware: firmware, directory: settings.downloadDirectory, demo: settings.demoMode)
            selection = .downloads
        }
    }

    func importIPSW() {
        guard let firmware = selectedFirmware else {
            lastError = L10n.text("Сначала выберите версию IPSW в библиотеке.", "Select an IPSW version in the library first.", language)
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ipsw") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = L10n.text("Выберите IPSW", "Choose IPSW", language)
        guard panel.runModal() == .OK, let source = panel.url else { return }
        status = L10n.text("Проверка IPSW", "Validating IPSW", language)
        sessionPhase = .validating
        Task {
            do {
                try await Task.detached { try IPSWValidator.validate(url: source, firmware: firmware) }.value
                settings.ensureDownloadDirectory()
                let destination = localURL(for: firmware)
                if source.standardizedFileURL != destination.standardizedFileURL {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: source, to: destination)
                }
                downloadedPath = destination.path
                sessionPhase = .connected
                status = L10n.text("IPSW импортирован", "IPSW imported", language)
                detail = destination.path
                updateCacheSize()
            } catch {
                quarantine(source)
                sessionPhase = .failed
                lastError = error.localizedDescription
                status = L10n.text("IPSW отклонён", "IPSW rejected", language)
                detail = error.localizedDescription
            }
        }
    }

    func isDownloaded(_ firmware: Firmware) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: firmware).path)
    }

    func revealDownloads() { NSWorkspace.shared.activateFileViewerSelecting([settings.downloadDirectory]) }

    func clearCache() {
        guard !downloads.phase.isActive else {
            lastError = L10n.text("Остановите текущую загрузку перед очисткой кэша.", "Stop the active download before clearing cache.", language)
            return
        }
        for file in CacheInspector.ipswFiles(in: settings.downloadDirectory) {
            try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
        }
        downloadedPath = nil
        updateCacheSize()
    }

    func updateCacheSize() { cacheSize = CacheInspector.size(in: settings.downloadDirectory) }

    func exportSupportBundle() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Target-Mac-DFU-Support-\(DateFormatter.bundleDate.string(from: Date())).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backend.demoMode = settings.demoMode
        Task {
            do {
                let output = try await backend.run(["support-bundle", url.path], onOutput: nil)
                status = L10n.text("Диагностика экспортирована", "Diagnostics exported", language)
                detail = output
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { lastError = error.localizedDescription }
        }
    }

    func exportHistoryCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Target-Mac-DFU-History-\(DateFormatter.bundleDate.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var rows = ["started_at,completed_at,operation,device,ecid,macos,build,result,detail"]
        for record in history.records {
            let values = [
                ISO8601DateFormatter().string(from: record.startedAt),
                record.completedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                record.operation.rawValue, record.deviceType, record.maskedECID,
                record.firmwareVersion, record.firmwareBuild, record.result, record.detail
            ]
            rows.append(values.map(Self.csvField).joined(separator: ","))
        }
        do {
            try (rows.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { lastError = error.localizedDescription }
    }

    private func downloadFinished(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            downloadedPath = url.path
            sessionPhase = .connected
            status = L10n.text("Загрузка завершена", "Download complete", language)
            detail = url.path
            updateCacheSize()
            if let job = pendingJob {
                pendingJob = nil
                Task { await runRecovery(kind: job.kind, device: job.device, firmware: job.firmware, file: url) }
            }
        case .failure(let error):
            sessionPhase = .failed
            lastError = error.localizedDescription
            status = L10n.text("Ошибка загрузки", "Download failed", language)
            detail = error.localizedDescription
            pendingJob = nil
        }
    }

    private func runRecovery(kind: RecoveryKind, device: DeviceInfo, firmware: Firmware, file: URL) async {
        guard !busy else { return }
        busy = true
        sessionPhase = .validating
        status = L10n.text("Проверка IPSW", "Validating IPSW", language)
        detail = L10n.text("Размер и контрольная сумма", "File size and checksum", language)
        do {
            try await Task.detached { try IPSWValidator.validate(url: file, firmware: firmware) }.value
            let detectOutput = try await backend.run(["detect"], onOutput: nil)
            let current = try JSONDecoder().decode(DeviceInfo.self, from: Data(detectOutput.utf8))
            guard current.ecid == device.ecid, current.type == device.type else {
                throw AppError.message("Подключённое устройство изменилось. Операция остановлена до повторного выбора.")
            }
            sessionPhase = .recovering
            recoveryProgress = 0
                status = "Restore"
            detail = L10n.text("Не отключайте кабель и питание", "Do not disconnect cable or power", language)
            let recordID = history.begin(kind: kind, device: device, firmware: firmware)
            do {
                _ = try await backend.run(["recover", kind.rawValue, device.ecid, file.path]) { [weak self] chunk in
                    guard let percent = Self.percent(in: chunk) else { return }
                    Task { @MainActor in self?.recoveryProgress = percent }
                }
                recoveryProgress = 1
                sessionPhase = .completed
                status = L10n.text("Операция завершена", "Operation complete", language)
                detail = L10n.text("Target Mac перезагрузится в Ассистент настройки.", "Target Mac will restart into Setup Assistant.", language)
                history.finish(id: recordID, result: "success", detail: detail)
            } catch {
                sessionPhase = .recoveryNeeded
                status = L10n.text("Требуется восстановление", "Recovery needed", language)
                detail = error.localizedDescription
                history.finish(id: recordID, result: "failed", detail: error.localizedDescription)
                throw error
            }
        } catch {
            lastError = error.localizedDescription
            if sessionPhase != .recoveryNeeded { sessionPhase = .failed }
            status = L10n.text("Операция остановлена", "Operation stopped", language)
            detail = error.localizedDescription
        }
        busy = false
    }

    private func confirm(kind: RecoveryKind, device: DeviceInfo, firmware: Firmware) -> Bool {
        let first = NSAlert()
        first.alertStyle = .critical
        first.messageText = L10n.text("Restore полностью сотрёт target Mac", "Restore will completely erase the target Mac", language)
        let betaWarning = firmware.isBeta
            ? L10n.text("\n\n⚠️ Выбрана предварительная beta/RC-сборка. Совместимость не гарантируется; необходима резервная копия.", "\n\n⚠️ A prerelease beta/RC build is selected. Compatibility is not guaranteed; keep a backup.", language)
            : ""
        first.informativeText = "\(device.type) · ECID \(device.maskedECID)\nmacOS \(firmware.version) (\(firmware.build))\n\n" + L10n.text("Все пользовательские данные будут удалены без возможности отмены.", "All user data will be irreversibly erased.", language) + betaWarning
        first.addButton(withTitle: "Restore")
        first.addButton(withTitle: L10n.text("Отмена", "Cancel", language))
        guard first.runModal() == .alertFirstButtonReturn else { return false }
        let second = NSAlert()
        second.alertStyle = .critical
        second.messageText = L10n.text("Последнее подтверждение стирания", "Final erase confirmation", language)
        second.informativeText = L10n.text(
            "Убедитесь, что выбрана модель \(device.type) с ECID \(device.maskedECID). После продолжения данные будут стёрты.",
            "Verify model \(device.type), ECID \(device.maskedECID). Continuing will erase all data.",
            language
        )
        second.addButton(withTitle: L10n.text("Стереть и восстановить", "Erase and Restore", language))
        second.addButton(withTitle: L10n.text("Назад", "Back", language))
        return second.runModal() == .alertFirstButtonReturn
    }

    private func localURL(for firmware: Firmware) -> URL {
        settings.downloadDirectory.appendingPathComponent(firmware.filename)
    }

    private func firmwareSourceArguments() throws -> (kind: FirmwareSourceKind, value: String) {
        switch settings.firmwareSource {
        case .ipswMe:
            return (.ipswMe, "")
        case .ipswBeta:
            return (.ipswBeta, "")
        case .customURL:
            let value = settings.customFirmwareURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: value), url.scheme?.lowercased() == "https" else {
                throw AppError.message("Для собственного источника укажите корректный HTTPS URL JSON-каталога.")
            }
            return (.customURL, value)
        case .localCatalog:
            let path = settings.localCatalogPath
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
                throw AppError.message("Выберите существующий локальный JSON-каталог IPSW.")
            }
            return (.localCatalog, path)
        case .bundled:
            let resources = ProcessInfo.processInfo.environment["TARGET_MAC_DFU_RESOURCES"]
                ?? Bundle.main.resourcePath
                ?? ""
            let path = resources + "/firmware-catalog.json"
            guard FileManager.default.fileExists(atPath: path) else {
                throw AppError.message("Встроенный каталог firmware-catalog.json отсутствует.")
            }
            return (.bundled, path)
        }
    }

    private func hasDownloadSpace(for firmware: Firmware) -> Bool {
        settings.ensureDownloadDirectory()
        let values = try? settings.downloadDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return true }
        let reserve: Int64 = 2_000_000_000
        let expectedSize = firmware.size > 0 ? firmware.size : 30_000_000_000
        guard available >= expectedSize + reserve else {
            let needed = ByteCountFormatter.string(fromByteCount: expectedSize + reserve, countStyle: .file)
            let free = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            lastError = L10n.text(
                "Недостаточно места: требуется около \(needed), свободно \(free).",
                "Not enough disk space: about \(needed) required, \(free) available.",
                language
            )
            return false
        }
        return true
    }

    private func quarantine(_ url: URL) {
        guard url.path.hasPrefix(settings.downloadDirectory.path) else { return }
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".invalid")
        try? FileManager.default.moveItem(at: url, to: destination)
    }

    private static func percent(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]{1,3})(?:\.[0-9]+)?%"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]) else { return nil }
        return min(1, max(0, value / 100))
    }

    private static func csvField(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension DateFormatter {
    static let bundleDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
