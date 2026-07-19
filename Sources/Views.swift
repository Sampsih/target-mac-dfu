import SwiftUI
import AppKit

struct GlassCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.4)) }
            .shadow(color: .black.opacity(0.06), radius: 14, y: 7)
    }
}

struct Sidebar: View {
    @Binding var selection: SectionItem
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 9) {
                Image(systemName: "laptopcomputer.and.arrow.down")
                    .font(.system(size: 42))
                    .frame(width: 82, height: 82)
                    .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .foregroundStyle(.white)
                Text("Target Mac DFU").font(.title2.bold())
                Text("Guided DFU & Restore").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 16)

            VStack(spacing: 5) {
                ForEach(SectionItem.allCases) { item in
                    Button {
                        selection = item
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).frame(width: 22)
                            Text(item.title(settings.language))
                            Spacer()
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 43)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == item ? .white : .secondary)
                    .background(
                        selection == item ? AnyShapeStyle(.blue.gradient) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                }
            }

            Spacer()
            Label(
                settings.demoMode
                    ? L10n.text("Демо-адаптер", "Demo adapter", settings.language)
                    : L10n.text("Безопасный режим", "Safety mode", settings.language),
                systemImage: settings.demoMode ? "testtube.2" : "checkmark.shield.fill"
            )
            .font(.caption.bold())
            .foregroundStyle(settings.demoMode ? .orange : .green)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(16)
        .frame(width: 270)
        .background(.ultraThinMaterial)
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $model.selection, settings: settings)
            VStack(spacing: 0) {
                ScrollView {
                    Group {
                        switch model.selection {
                        case .overview: OverviewView(model: model)
                        case .dfu: DFUGuideView(model: model)
                        case .info: DeviceInfoView(model: model)
                        case .library: LibraryView(model: model)
                        case .downloads: DownloadsView(model: model)
                        case .restore: RecoveryView(model: model)
                        case .history: HistoryView(model: model)
                        case .settings: SettingsView(model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 760, alignment: .top)
                    .padding(24)
                }
                StatusBar(model: model)
            }
        }
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), .blue.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .alert(
            "Target Mac DFU",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: { Text(model.lastError ?? "") }
        .onChange(of: settings.demoMode) {
            Task { await model.refreshDevice(silent: false) }
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var action: AnyView?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            action
        }
        .padding(.bottom, 4)
    }
}

struct ToolSetupCard: View {
    @ObservedObject var model: AppModel
    var compact = false

    var body: some View {
        GlassCard {
            HStack(spacing: 16) {
                Image(systemName: model.cfgutilReady ? "checkmark.seal.fill" : "wrench.and.screwdriver.fill")
                    .font(.system(size: compact ? 30 : 38))
                    .foregroundStyle(model.cfgutilReady ? .green : .orange)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                    if let path = model.toolStatus?.cfgutilPath, !path.isEmpty {
                        Text(path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Spacer()
                if model.toolStatus == nil {
                    ProgressView().controlSize(.small)
                } else if !model.cfgutilReady {
                    Button(actionTitle, systemImage: model.toolStatus?.configuratorInstalled == true ? "arrow.up.forward.app" : "bag.fill") {
                        model.openConfiguratorSetup()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(L10n.text("Проверить снова", "Check Again", model.language), systemImage: "arrow.clockwise") {
                    model.checkToolchainNow()
                }
                Button("", systemImage: "questionmark.circle") { model.openConfiguratorHelp() }
                    .help(L10n.text("Инструкция Apple", "Apple instructions", model.language))
            }
        }
    }

    private var title: String {
        if model.cfgutilReady { return L10n.text("Automation Tools готовы", "Automation Tools Ready", model.language) }
        if model.toolStatus?.configuratorInstalled == true {
            return L10n.text("Установите Automation Tools", "Install Automation Tools", model.language)
        }
        return L10n.text("Требуется Apple Configurator", "Apple Configurator Required", model.language)
    }

    private var detail: String {
        if model.cfgutilReady { return L10n.text("cfgutil найден — обнаружение DFU доступно.", "cfgutil found — DFU detection is available.", model.language) }
        if model.toolStatus?.configuratorInstalled == true {
            return L10n.text("Откройте Configurator → Install Automation Tools…, подтвердите пароль администратора.", "Open Configurator → Install Automation Tools… and approve the administrator prompt.", model.language)
        }
        return L10n.text("Установите бесплатный Apple Configurator из Mac App Store.", "Install the free Apple Configurator from the Mac App Store.", model.language)
    }

    private var actionTitle: String {
        model.toolStatus?.configuratorInstalled == true
            ? L10n.text("Открыть Configurator", "Open Configurator", model.language)
            : L10n.text("Установить", "Install", model.language)
    }
}

struct OverviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            PageHeader(
                title: L10n.text("Обзор", "Overview", model.language),
                subtitle: model.detail,
                action: AnyView(
                    Button(
                        model.device == nil
                            ? L10n.text("Войти в DFU", "Enter DFU", model.language)
                            : L10n.text("Обновить", "Refresh", model.language),
                        systemImage: model.device == nil ? "power" : "arrow.clockwise"
                    ) {
                        if model.device == nil { model.enterDFU() }
                        else { Task { await model.refreshDevice(silent: false) } }
                    }
                    .controlSize(.large)
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(model.busy)
                )
            )

            if model.toolStatus != nil, !model.cfgutilReady, !model.settings.demoMode {
                ToolSetupCard(model: model, compact: true)
                    .frame(height: 104)
            }

            HStack(alignment: .top, spacing: 18) {
                DeviceSummaryCard(model: model)
                SafetyStepsCard(model: model).frame(width: 390)
            }
            .frame(height: 270)
            HStack(alignment: .top, spacing: 18) {
                FirmwareList(model: model, compact: true)
                QuickRecoveryCard(model: model).frame(width: 390)
            }
            .frame(height: 360)
        }
    }
}

struct DeviceSummaryCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GlassCard {
            HStack(spacing: 24) {
                Image(systemName: model.device == nil ? "laptopcomputer.slash" : "laptopcomputer")
                    .resizable().scaledToFit().frame(width: 180, height: 125)
                    .symbolRenderingMode(.hierarchical).foregroundStyle(model.device == nil ? .gray : .blue)
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.deviceName).font(.title2.bold())
                    Divider()
                    InfoRow(title: "Model Identifier", value: model.device?.type ?? "—")
                    InfoRow(title: "ECID", value: model.device?.maskedECID ?? "—")
                    InfoRow(title: "Mode", value: model.device?.mode ?? "Disconnected", accent: model.device == nil ? .secondary : .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .accessibilityElement(children: .combine)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var accent: Color = .primary
    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).foregroundStyle(accent).textSelection(.enabled)
            Spacer()
        }
    }
}

struct SafetyStepsCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                Label(
                    model.device == nil
                        ? L10n.text("Ожидание Mac", "Waiting for Mac", model.language)
                        : "DFU Mode",
                    systemImage: model.device == nil ? "cable.connector" : "checkmark.circle.fill"
                )
                .font(.headline).foregroundStyle(model.device == nil ? Color.secondary : Color.green)
                step(1, L10n.text("Проверьте DFU-порт", "Check the DFU port", model.language), L10n.text("Откройте официальную таблицу Apple.", "Open Apple's official port table.", model.language))
                step(2, L10n.text("Нажмите «Войти в DFU»", "Choose Enter DFU", model.language), L10n.text("Приложение отправит аппаратную команду.", "The app sends the hardware command.", model.language))
                step(3, L10n.text("Проверьте DFU", "Verify DFU", model.language), L10n.text("Дождитесь модели и последних цифр ECID.", "Wait for the model and final ECID digits.", model.language))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(.caption.bold()).frame(width: 23, height: 23).background(.gray.opacity(0.22), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct FirmwareList: View {
    @ObservedObject var model: AppModel
    let compact: Bool

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading) {
                        Text((model.settings.includeBetaFirmwares || model.settings.firmwareSource == .ipswBeta)
                            ? L10n.text("IPSW, включая beta", "IPSW, including beta", model.language)
                            : L10n.text("Доступные IPSW", "Available IPSW", model.language)).font(.title2.bold())
                        Text(model.settings.firmwareSource.title(model.language)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text("Обновить", "Refresh", model.language), systemImage: "arrow.clockwise") { model.refreshFirmwares() }
                        .disabled(model.busy || model.device == nil)
                }
                if model.firmwares.isEmpty {
                    ContentUnavailableView(
                        L10n.text("IPSW пока нет", "No IPSW yet", model.language),
                        systemImage: "externaldrive.badge.questionmark",
                        description: Text(model.device == nil
                            ? L10n.text("Сначала подключите Mac в DFU", "Connect a Mac in DFU first", model.language)
                            : L10n.text("Обновите каталог", "Refresh the catalog", model.language))
                    )
                    .frame(minHeight: compact ? 190 : 330)
                } else {
                    VStack(spacing: 5) {
                        ForEach(compact ? Array(model.firmwares.prefix(4)) : model.firmwares) { firmware in
                            FirmwareRow(model: model, firmware: firmware)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FirmwareRow: View {
    @ObservedObject var model: AppModel
    let firmware: Firmware
    var body: some View {
        let selected = model.selectedFirmware == firmware
        Button {
            model.selectedFirmware = firmware
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("macOS \(firmware.version)").font(.headline)
                        if firmware.isBeta {
                            Text("BETA").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.22), in: Capsule()).foregroundStyle(selected ? .white : .orange)
                        }
                    }
                    Text("\(firmware.build) · \(firmware.date)").font(.caption).opacity(0.8)
                }
                Spacer()
                Text(firmware.size > 0 ? firmware.sizeText : L10n.text("Размер при загрузке", "Size on download", model.language)).font(.caption)
                Image(systemName: model.isDownloaded(firmware) ? "checkmark.icloud.fill" : "icloud.and.arrow.down")
                    .foregroundStyle(model.isDownloaded(firmware) ? .green : (selected ? .white : .secondary))
            }
            .padding(.horizontal, 11).frame(height: 50)
            .foregroundStyle(selected ? .white : .primary)
            .background(selected ? AnyShapeStyle(.blue.gradient) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.downloads.phase.isActive)
        .accessibilityLabel("macOS \(firmware.version), build \(firmware.build), \(firmware.sizeText)")
    }
}

struct QuickRecoveryCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 15) {
                Text(L10n.text("Следующее действие", "Next Action", model.language)).font(.title2.bold())
                Label(L10n.text("Restore — стереть и восстановить", "Restore — erase and reinstall", model.language), systemImage: "externaldrive.badge.xmark")
                    .font(.headline)
                Text(L10n.text("Полностью стирает Target Mac и восстанавливает его заново. Требует двойного подтверждения.", "Completely erases the target Mac and restores it. Requires double confirmation.", model.language))
                    .font(.caption).foregroundStyle(.red)
                Spacer()
                Button(L10n.text("Запустить Restore", "Start Restore", model.language), systemImage: "externaldrive.badge.xmark") { model.requestRecovery() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.device == nil || model.selectedFirmware == nil || model.busy || model.downloads.phase.isActive)
                Button(L10n.text("Только скачать", "Download Only", model.language), systemImage: "arrow.down.to.line") { model.downloadOnly() }
                    .buttonStyle(.bordered).disabled(model.selectedFirmware == nil || model.downloads.phase.isActive)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct DFUGuideView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: L10n.text("DFU одним нажатием", "One-Click DFU", model.language),
                subtitle: L10n.text("Подключите Target Mac кабелем и отправьте аппаратную команду DFU.", "Connect the target Mac and send the hardware DFU command.", model.language),
                action: AnyView(Button(L10n.text("Проверить DFU", "Check DFU", model.language), systemImage: "arrow.clockwise") { model.checkDFUPresenceNow() }.disabled(model.busy))
            )
            GlassCard {
                HStack(spacing: 24) {
                    Image(systemName: model.device == nil ? "bolt.horizontal.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(model.device == nil ? .blue : .green)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.device == nil
                            ? L10n.text("Автоматически отправить Mac в DFU", "Send Mac to DFU Automatically", model.language)
                            : L10n.text("Mac уже находится в DFU", "Mac Is Already in DFU", model.language))
                            .font(.title2.bold())
                        Text(L10n.text(
                            "Подключите Target Mac напрямую к Host Mac. Кабель вставьте в DFU-порт Target Mac — нужный порт можно проверить по таблице Apple. Host Mac должен быть на Apple silicon.",
                            "Connect the target Mac directly to the host Mac. Use the target Mac DFU port, shown in Apple's table. The host Mac must use Apple silicon.",
                            model.language
                        )).foregroundStyle(.secondary)
                        HStack {
                            Button(L10n.text("Отправить Mac в DFU", "Send Mac to DFU", model.language), systemImage: "power") { model.enterDFU() }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(model.busy || model.device != nil)
                            Button(L10n.text("Таблица DFU-портов Apple", "Apple DFU Port Table", model.language), systemImage: "safari") { model.openAppleDFUPortGuide() }
                            Button(L10n.text("Открыть Finder", "Open Finder", model.language), systemImage: "face.smiling") { model.openFinder() }
                        }
                        if model.busy {
                            ProgressView().controlSize(.small)
                        }
                        Text(model.detail).font(.caption).foregroundStyle(model.sessionPhase == .failed ? .red : .secondary)
                    }
                    Spacer()
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 15) {
                    Label(L10n.text("Запасной вариант: ручной вход в DFU", "Fallback: Manual DFU Entry", model.language), systemImage: "hand.raised.fill")
                        .font(.title2.bold())
                    Text(L10n.text("Используйте только если кнопка выше не сработала. Сначала подключите кабель в правильный DFU-порт.", "Use this only if the button above fails. First connect the cable to the correct DFU port.", model.language))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 18) {
                        manualCard(
                            L10n.text("MacBook с Apple silicon", "Apple silicon MacBook", model.language),
                            L10n.text("1. Удерживайте Power/Touch ID до 10 секунд, пока Mac не выключится.\n2. Нажмите и отпустите Power, затем сразу зажмите вместе: левый Control, левый Option, правый Shift и Power.\n3. Держите все четыре клавиши около 10 секунд.\n4. Отпустите Control, Option и Shift, но продолжайте удерживать Power ещё до 10 секунд, пока DFU не появится в Finder.", "1. Hold Power/Touch ID for up to 10 seconds until the Mac turns off.\n2. Press and release Power, then immediately hold left Control, left Option, right Shift, and Power together.\n3. Hold all four for about 10 seconds.\n4. Release Control, Option, and Shift, but keep holding Power for up to 10 more seconds until DFU appears in Finder.", model.language)
                        )
                        manualCard(
                            L10n.text("MacBook с чипом T2", "T2 MacBook", model.language),
                            L10n.text("1. Удерживайте Power/Touch ID до 10 секунд, пока Mac не выключится.\n2. Нажмите и отпустите Power, затем сразу зажмите вместе: левый Control, левый Option, правый Shift и Power.\n3. Держите все четыре клавиши около 3 секунд, пока DFU не появится в Finder.", "1. Hold Power/Touch ID for up to 10 seconds until the Mac turns off.\n2. Press and release Power, then immediately hold left Control, left Option, right Shift, and Power together.\n3. Hold all four for about 3 seconds until DFU appears in Finder.", model.language)
                        )
                        manualCard(
                            L10n.text("Настольный Mac", "Desktop Mac", model.language),
                            L10n.text("1. Отключите Target Mac от питания.\n2. Нажмите и удерживайте кнопку Power.\n3. Не отпуская Power, подключите питание.\n4. Продолжайте удерживать Power до 10 секунд, пока DFU не появится в Finder.", "1. Unplug the target Mac from power.\n2. Press and hold Power.\n3. While holding Power, reconnect power.\n4. Keep holding Power for up to 10 seconds until DFU appears in Finder.", model.language)
                        )
                    }
                    Link(L10n.text("Полная официальная инструкция Apple", "Full Official Apple Guide", model.language), destination: URL(string: "https://support.apple.com/108900")!)
                }
            }
        }
    }

    private func manualCard(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct DeviceInfoView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: L10n.text("Устройство", "Device Info", model.language), subtitle: L10n.text("Сессия привязана к ECID; смена устройства блокирует операцию.", "The session is bound to ECID; a device change blocks the operation.", model.language), action: nil)
            DeviceSummaryCard(model: model)
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.text("Правила безопасности", "Safety Rules", model.language), systemImage: "lock.shield.fill").font(.title2.bold())
                    Text(L10n.text("• Одно устройство на сессию.\n• Точная модель и ECID повторно проверяются перед RecoveryJob.\n• Потеря USB переводит процесс в детерминированное состояние Recovery Needed.\n• Чувствительный ECID маскируется в истории и support bundle.", "• One device per session.\n• Exact model and ECID are rechecked before RecoveryJob.\n• USB loss produces a deterministic Recovery Needed state.\n• Sensitive ECID is masked in history and support bundles.", model.language))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct LibraryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: L10n.text("Библиотека IPSW", "IPSW Library", model.language),
                subtitle: L10n.text("Совместимые образы из выбранного каталога для определённой модели.", "Model-compatible images from the selected device catalog.", model.language),
                action: AnyView(HStack {
                    Button(L10n.text("Импорт IPSW", "Import IPSW", model.language), systemImage: "square.and.arrow.down") { model.importIPSW() }
                    Button(L10n.text("Обновить", "Refresh", model.language), systemImage: "arrow.clockwise") { model.refreshFirmwares() }.disabled(model.device == nil)
                })
            )
            FirmwareList(model: model, compact: false)
            GlassCard {
                HStack {
                    Label(L10n.text("Проверка перед использованием: размер и SHA-1 из доверенного каталога. Несовпадение блокирует операцию.", "Pre-use validation: catalog size and SHA-1. Any mismatch blocks the operation.", model.language), systemImage: "checkmark.seal.fill")
                    Spacer()
                    Text(model.lastCatalogRefresh?.formatted(date: .abbreviated, time: .shortened) ?? "—").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct DownloadsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var manager = DownloadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: L10n.text("Загрузки", "Downloads", model.language),
                subtitle: model.settings.downloadDirectoryPath,
                action: AnyView(Button(L10n.text("Показать в Finder", "Show in Finder", model.language), systemImage: "folder") { model.revealDownloads() })
            )
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: manager.phase == .completed ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 38)).foregroundStyle(manager.phase == .completed ? .green : .blue)
                        VStack(alignment: .leading) {
                            Text(manager.activeFirmware.map { "macOS \($0.version) (\($0.build))" } ?? L10n.text("Нет активной загрузки", "No active download", model.language)).font(.title2.bold())
                            Text(manager.activeFirmware?.filename ?? L10n.text("Выберите IPSW в библиотеке", "Choose an IPSW in the library", model.language)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(manager.speedText).monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: manager.progress).progressViewStyle(.linear).tint(.blue)
                    HStack {
                        Text(manager.progressText).monospacedDigit().font(.headline)
                        Spacer()
                        phaseText
                    }
                    HStack {
                        if manager.phase == .downloading {
                            Button(L10n.text("Пауза", "Pause", model.language), systemImage: "pause.fill") { manager.pause() }
                                .keyboardShortcut("p", modifiers: [.command])
                        } else if manager.phase == .paused {
                            Button(L10n.text("Продолжить", "Resume", model.language), systemImage: "play.fill") { manager.resume() }
                                .buttonStyle(.borderedProminent).keyboardShortcut("p", modifiers: [.command])
                        }
                        if manager.phase == .downloading || manager.phase == .paused {
                            Button(L10n.text("Отменить", "Cancel", model.language), systemImage: "xmark", role: .destructive) { manager.cancel() }
                        }
                        Spacer()
                        Button(L10n.text("Изменить папку…", "Change Folder…", model.language), systemImage: "folder.badge.gearshape") { model.settings.chooseDownloadDirectory() }
                            .disabled(manager.phase.isActive)
                    }
                }
                .frame(minHeight: 220)
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Продолжение после перезапуска", "Resume after restart", model.language)).font(.headline)
                    Text(L10n.text("При штатном выходе активная URLSession-загрузка сохраняет resume-data. После следующего запуска она отображается как приостановленная и может быть продолжена.", "On normal quit, the active URLSession download saves resume data. On the next launch it appears paused and can be resumed.", model.language)).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var phaseText: some View {
        switch manager.phase {
        case .idle: Text(L10n.text("Ожидание", "Idle", model.language)).foregroundStyle(.secondary)
        case .downloading: Text(L10n.text("Скачивается", "Downloading", model.language)).foregroundStyle(.blue)
        case .paused: Text(L10n.text("Приостановлено", "Paused", model.language)).foregroundStyle(.orange)
        case .validating: Text(L10n.text("Проверка", "Validating", model.language)).foregroundStyle(.orange)
        case .completed: Text(L10n.text("Готово", "Complete", model.language)).foregroundStyle(.green)
        case .failed(let error): Text(error).foregroundStyle(.red).lineLimit(2)
        }
    }
}

struct RecoveryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: L10n.text("Restore", "Restore", model.language), subtitle: L10n.text("Полное стирание, повторная проверка ECID и двойное подтверждение.", "Full erase, ECID recheck, and double confirmation.", model.language), action: nil)
            HStack(alignment: .top, spacing: 18) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(L10n.text("Restore — стереть и восстановить", "Restore — erase and reinstall", model.language), systemImage: "externaldrive.badge.xmark")
                            .font(.title2.bold()).foregroundStyle(.red)
                        Text(L10n.text("Все данные на Target Mac будут удалены. После завершения Mac запустит Ассистент настройки.", "All data on the target Mac will be erased. Setup Assistant starts when complete.", model.language))
                            .foregroundStyle(.secondary)
                        Button(L10n.text("Запустить Restore", "Start Restore", model.language), systemImage: "externaldrive.badge.xmark") { model.requestRecovery() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(model.device == nil || model.selectedFirmware == nil || model.busy || model.downloads.phase.isActive)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.text("Предварительная проверка", "Preflight", model.language)).font(.title2.bold())
                        check(model.device != nil, L10n.text("Устройство и ECID определены", "Device and ECID detected", model.language))
                        check(model.selectedFirmware != nil, L10n.text("Совместимая IPSW выбрана", "Compatible IPSW selected", model.language))
                        check(model.selectedFirmware.map(model.isDownloaded) ?? false, L10n.text("IPSW загружена (иначе загрузится автоматически)", "IPSW downloaded (otherwise downloads automatically)", model.language))
                        check(!model.downloads.phase.isActive, L10n.text("Нет другой активной загрузки", "No other active download", model.language))
                        Divider()
                        Text(L10n.text("Во время активного RecoveryJob кнопка отмены намеренно отсутствует: cfgutil должен завершить безопасную точку сам.", "During an active RecoveryJob there is intentionally no cancel button; cfgutil must reach its own safe point.", model.language)).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 390)
                }
            }
            if model.isRecoveryRunning {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(model.status, systemImage: "wrench.and.screwdriver.fill").font(.title2.bold())
                        ProgressView(value: model.recoveryProgress)
                        Text("\(Int(model.recoveryProgress * 100))% · \(model.detail)").monospacedDigit()
                    }
                }
            }
        }
    }

    private func check(_ passed: Bool, _ text: String) -> some View {
        Label(text, systemImage: passed ? "checkmark.circle.fill" : "circle").foregroundStyle(passed ? .green : .secondary)
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var history = HistoryStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: L10n.text("История", "History", model.language),
                subtitle: L10n.text("Локальная история операций с маскированным ECID.", "Local operation history with masked ECID.", model.language),
                action: AnyView(HStack {
                    Button(L10n.text("Support bundle", "Support Bundle", model.language), systemImage: "shippingbox") { model.exportSupportBundle() }
                    Button("CSV", systemImage: "tablecells") { model.exportHistoryCSV() }.disabled(history.records.isEmpty)
                    Button(L10n.text("Очистить", "Clear", model.language), role: .destructive) { history.clear() }.disabled(history.records.isEmpty)
                })
            )
            GlassCard {
                if history.records.isEmpty {
                    ContentUnavailableView(L10n.text("Операций пока нет", "No operations yet", model.language), systemImage: "clock", description: Text(L10n.text("Завершённые Restore появятся здесь.", "Completed Restore jobs appear here.", model.language))).frame(minHeight: 330)
                } else {
                    VStack(spacing: 6) {
                        ForEach(history.records) { record in
                            HStack(spacing: 12) {
                                Image(systemName: record.result == "success" ? "checkmark.circle.fill" : record.result == "running" ? "hourglass.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(record.result == "success" ? .green : record.result == "running" ? .orange : .red)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(record.operation.rawValue.capitalized) · \(record.deviceType)").font(.headline)
                                    Text("macOS \(record.firmwareVersion) (\(record.firmwareBuild)) · ECID \(record.maskedECID)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    Text(record.result).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(10).background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = AppSettings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: L10n.text("Настройки", "Settings", settings.language), subtitle: L10n.text("Хранилище, язык, диагностика и тестовый адаптер.", "Storage, language, diagnostics, and test adapter.", settings.language), action: nil)
            ToolSetupCard(model: model)
            GlassCard {
                VStack(alignment: .leading, spacing: 15) {
                    Label(L10n.text("Папка IPSW по умолчанию", "Default IPSW Folder", settings.language), systemImage: "folder.fill").font(.title2.bold())
                    Text(settings.downloadDirectoryPath).textSelection(.enabled).foregroundStyle(.secondary)
                    HStack {
                        Button(L10n.text("Выбрать папку…", "Choose Folder…", settings.language), systemImage: "folder.badge.gearshape") { settings.chooseDownloadDirectory(); model.updateCacheSize() }.disabled(model.downloads.phase.isActive)
                        Button(L10n.text("Сбросить", "Reset", settings.language)) { settings.resetDownloadDirectory(); model.updateCacheSize() }.disabled(model.downloads.phase.isActive)
                        Button(L10n.text("Открыть", "Open", settings.language)) { model.revealDownloads() }
                    }
                    Divider()
                    HStack {
                        Text(L10n.text("Размер кэша", "Cache Size", settings.language))
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: model.cacheSize, countStyle: .file)).monospacedDigit()
                    }
                    HStack {
                        Text(L10n.text("Лимит кэша", "Cache Limit", settings.language))
                        Slider(value: $settings.cacheLimitGB, in: 10...500, step: 10).frame(maxWidth: 330)
                        Text("\(Int(settings.cacheLimitGB)) GB").monospacedDigit().frame(width: 65)
                    }
                    Button(L10n.text("Переместить кэш в Корзину", "Move Cache to Trash", settings.language), systemImage: "trash", role: .destructive) { model.clearCache() }.disabled(model.downloads.phase.isActive)
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label(L10n.text("Источник IPSW", "IPSW Source", settings.language), systemImage: "server.rack").font(.title2.bold())
                    Picker(L10n.text("Каталог", "Catalog", settings.language), selection: $settings.firmwareSource) {
                        ForEach(FirmwareSourceKind.allCases) { source in
                            Text(source.title(settings.language)).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                    switch settings.firmwareSource {
                    case .ipswMe:
                        Text(L10n.text("Публичный каталог IPSW.me. Ответ кэшируется для работы при временном сбое сети.", "Public IPSW.me catalog. Responses are cached for temporary network outages.", settings.language))
                            .font(.caption).foregroundStyle(.secondary)
                    case .ipswBeta:
                        Text(L10n.text("Beta-каталог IPSWBeta.dev. Принимаются только ссылки на официальный Apple CDN; актуальность подписи окончательно проверяется средствами Apple при Restore.", "IPSWBeta.dev beta catalog. Only official Apple CDN links are accepted; Apple tools make the final signing check during Restore.", settings.language))
                            .font(.caption).foregroundStyle(.orange)
                    case .customURL:
                        TextField("https://firmware.example.com/catalog.json", text: $settings.customFirmwareURL)
                            .textFieldStyle(.roundedBorder)
                        Text(L10n.text("Разрешён только HTTPS. Формат совместим с IPSW.me или внутренним manifest со списком devices/firmwares.", "HTTPS only. The format may match IPSW.me or an internal devices/firmwares manifest.", settings.language))
                            .font(.caption).foregroundStyle(.secondary)
                    case .localCatalog:
                        HStack {
                            Text(settings.localCatalogPath.isEmpty ? L10n.text("Файл не выбран", "No file selected", settings.language) : settings.localCatalogPath)
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.text("Выбрать JSON…", "Choose JSON…", settings.language), systemImage: "doc.badge.plus") { settings.chooseLocalCatalog() }
                        }
                    case .bundled:
                        Text(L10n.text("Используется Resources/firmware-catalog.json внутри приложения. Каталог изначально пуст и предназначен для корпоративной сборки.", "Uses Resources/firmware-catalog.json inside the app. It is initially empty and intended for a managed internal build.", settings.language))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if settings.firmwareSource == .ipswBeta {
                        Label(L10n.text("Beta-режим включён выбранным источником.", "Beta mode is enabled by this source.", settings.language), systemImage: "testtube.2")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Toggle(L10n.text("Показывать beta/RC версии из каталога", "Show beta/RC versions from catalog", settings.language), isOn: $settings.includeBetaFirmwares)
                    }
                    if settings.includeBetaFirmwares && settings.firmwareSource != .ipswBeta {
                        Label(L10n.text("Beta появится только если выбранный источник помечает запись как подписанную. Приложение не обходит проверки Apple.", "Beta appears only when the source marks the entry as signed. The app never bypasses Apple verification.", settings.language), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Button(L10n.text("Применить и обновить каталог", "Apply and Refresh Catalog", settings.language), systemImage: "arrow.clockwise") { model.refreshFirmwares() }
                            .disabled(model.device == nil || model.busy)
                        Spacer()
                        Link(L10n.text("Beta software Apple", "Apple Beta Software", settings.language), destination: URL(string: "https://developer.apple.com/support/install-beta")!)
                    }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.text("Интерфейс", "Interface", settings.language), systemImage: "character.bubble.fill").font(.title2.bold())
                        Picker(L10n.text("Язык", "Language", settings.language), selection: $settings.language) {
                            ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
                        }
                        .pickerStyle(.segmented)
                        Toggle(L10n.text("Автоматически обновлять каталог", "Automatically refresh catalog", settings.language), isOn: $settings.automaticCatalogRefresh)
                        Text(L10n.text("Основные действия имеют VoiceOver-метки и клавиатурные команды: ⌘R — обновить, ⌘P — пауза/продолжение.", "Primary actions include VoiceOver labels and keyboard commands: ⌘R refresh, ⌘P pause/resume.", settings.language)).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.text("Конфиденциальность и тесты", "Privacy & Testing", settings.language), systemImage: "hand.raised.fill").font(.title2.bold())
                        Toggle(L10n.text("Анонимная телеметрия (только с согласием)", "Anonymous telemetry (opt-in only)", settings.language), isOn: $settings.telemetryOptIn)
                        Text(L10n.text("В этой сборке endpoint телеметрии не настроен: данные никуда не отправляются.", "No telemetry endpoint is configured in this build; nothing is transmitted.", settings.language)).font(.caption).foregroundStyle(.secondary)
                        Toggle(L10n.text("Демо-режим без реального Mac", "Demo mode without a real Mac", settings.language), isOn: $settings.demoMode)
                        Text(L10n.text("Fake-адаптер позволяет пройти UI-сценарий и проверить ошибки без подключённого устройства.", "The fake adapter exercises the UI flow and errors without attached hardware.", settings.language)).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GlassCard {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Target Mac DFU \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")").font(.headline)
                        Text(L10n.text("Автообновление отключено: в исходном пакете не указан доверенный release feed.", "Auto-update is disabled: the source package does not define a trusted release feed.", settings.language)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text("Открыть журнал", "Open Log", settings.language), systemImage: "doc.text.magnifyingglass") {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TargetMacDFU.log"))
                    }
                }
            }
        }
    }
}

struct StatusBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var downloads = DownloadManager.shared
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(model.status).font(.headline)
            if downloads.phase == .downloading {
                ProgressView(value: downloads.progress).frame(width: 150)
                Text(downloads.progressText).monospacedDigit().font(.caption)
            } else if model.isRecoveryRunning {
                ProgressView(value: model.recoveryProgress).frame(width: 150)
                Text("\(Int(model.recoveryProgress * 100))%").monospacedDigit().font(.caption)
            }
            Spacer()
            Text(model.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 20).frame(height: 48).background(.ultraThinMaterial)
    }

    private var icon: String {
        switch model.sessionPhase {
        case .failed, .recoveryNeeded: return "exclamationmark.triangle.fill"
        case .downloading, .validating, .recovering, .detecting, .enteringDFU: return "hourglass"
        case .connected, .completed: return "checkmark.circle.fill"
        case .disconnected: return "circle.dashed"
        }
    }
    private var color: Color {
        switch model.sessionPhase {
        case .failed, .recoveryNeeded: return .red
        case .downloading, .validating, .recovering, .detecting, .enteringDFU: return .orange
        case .connected, .completed: return .green
        case .disconnected: return .secondary
        }
    }
}
