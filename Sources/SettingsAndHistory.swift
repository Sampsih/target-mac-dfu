import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let downloadDirectory = "downloadDirectory"
        static let language = "language"
        static let cacheLimitGB = "cacheLimitGB"
        static let telemetry = "telemetryOptIn"
        static let demoMode = "demoMode"
        static let automaticCatalogRefresh = "automaticCatalogRefresh"
        static let firmwareSource = "firmwareSource"
        static let customFirmwareURL = "customFirmwareURL"
        static let localCatalogPath = "localCatalogPath"
        static let includeBetaFirmwares = "includeBetaFirmwares"
    }

    private let defaults = UserDefaults.standard

    @Published var downloadDirectoryPath: String {
        didSet { defaults.set(downloadDirectoryPath, forKey: Key.downloadDirectory) }
    }
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }
    @Published var cacheLimitGB: Double {
        didSet { defaults.set(cacheLimitGB, forKey: Key.cacheLimitGB) }
    }
    @Published var telemetryOptIn: Bool {
        didSet { defaults.set(telemetryOptIn, forKey: Key.telemetry) }
    }
    @Published var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: Key.demoMode) }
    }
    @Published var automaticCatalogRefresh: Bool {
        didSet { defaults.set(automaticCatalogRefresh, forKey: Key.automaticCatalogRefresh) }
    }
    @Published var firmwareSource: FirmwareSourceKind {
        didSet { defaults.set(firmwareSource.rawValue, forKey: Key.firmwareSource) }
    }
    @Published var customFirmwareURL: String {
        didSet { defaults.set(customFirmwareURL, forKey: Key.customFirmwareURL) }
    }
    @Published var localCatalogPath: String {
        didSet { defaults.set(localCatalogPath, forKey: Key.localCatalogPath) }
    }
    @Published var includeBetaFirmwares: Bool {
        didSet { defaults.set(includeBetaFirmwares, forKey: Key.includeBetaFirmwares) }
    }

    private init() {
        let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/Target Mac DFU", isDirectory: true).path
        downloadDirectoryPath = defaults.string(forKey: Key.downloadDirectory) ?? defaultDirectory
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "ru") ?? .russian
        cacheLimitGB = defaults.object(forKey: Key.cacheLimitGB) == nil
            ? 80 : max(10, defaults.double(forKey: Key.cacheLimitGB))
        telemetryOptIn = defaults.bool(forKey: Key.telemetry)
        demoMode = defaults.bool(forKey: Key.demoMode)
        automaticCatalogRefresh = defaults.object(forKey: Key.automaticCatalogRefresh) == nil
            ? true : defaults.bool(forKey: Key.automaticCatalogRefresh)
        firmwareSource = FirmwareSourceKind(
            rawValue: defaults.string(forKey: Key.firmwareSource) ?? FirmwareSourceKind.ipswMe.rawValue
        ) ?? .ipswMe
        customFirmwareURL = defaults.string(forKey: Key.customFirmwareURL) ?? ""
        localCatalogPath = defaults.string(forKey: Key.localCatalogPath) ?? ""
        includeBetaFirmwares = defaults.bool(forKey: Key.includeBetaFirmwares)
        ensureDownloadDirectory()
    }

    var downloadDirectory: URL { URL(fileURLWithPath: downloadDirectoryPath, isDirectory: true) }

    func ensureDownloadDirectory() {
        try? FileManager.default.createDirectory(
            at: downloadDirectory,
            withIntermediateDirectories: true
        )
    }

    func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("Папка для IPSW", "IPSW Download Folder", language)
        panel.prompt = L10n.text("Выбрать", "Choose", language)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = downloadDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        downloadDirectoryPath = url.path
        ensureDownloadDirectory()
    }

    func resetDownloadDirectory() {
        downloadDirectoryPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/Target Mac DFU", isDirectory: true).path
        ensureDownloadDirectory()
    }

    func chooseLocalCatalog() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("JSON-каталог IPSW", "IPSW JSON Catalog", language)
        panel.prompt = L10n.text("Подключить", "Connect", language)
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if !localCatalogPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: localCatalogPath).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        localCatalogPath = url.path
        firmwareSource = .localCatalog
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var records: [HistoryRecord] = []

    private let fileURL: URL

    private init() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Target Mac DFU", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.history.decode([HistoryRecord].self, from: data) {
            records = decoded.sorted { $0.startedAt > $1.startedAt }
        }
    }

    func begin(kind: RecoveryKind, device: DeviceInfo, firmware: Firmware) -> UUID {
        let record = HistoryRecord(
            id: UUID(),
            startedAt: Date(),
            completedAt: nil,
            operation: kind,
            deviceType: device.type,
            maskedECID: device.maskedECID,
            firmwareVersion: firmware.version,
            firmwareBuild: firmware.build,
            result: "running",
            detail: ""
        )
        records.insert(record, at: 0)
        save()
        return record.id
    }

    func finish(id: UUID, result: String, detail: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].completedAt = Date()
        records[index].result = result
        records[index].detail = detail
        save()
    }

    func clear() {
        records.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder.history.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var history: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var history: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum CacheInspector {
    static func ipswFiles(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { ["ipsw", "part"].contains($0.pathExtension.lowercased()) }
    }

    static func size(in directory: URL) -> Int64 {
        ipswFiles(in: directory).reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    static func prune(directory: URL, limitGB: Double, excluding protectedURL: URL? = nil) {
        let limit = Int64(limitGB * 1_000_000_000)
        var files = ipswFiles(in: directory).filter { $0 != protectedURL }
        var total = size(in: directory)
        guard total > limit else { return }
        files.sort {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
        for file in files where total > limit {
            let bytes = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if (try? FileManager.default.removeItem(at: file)) != nil { total -= bytes }
        }
    }
}
