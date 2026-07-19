import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }
    var title: String { self == .russian ? "Русский" : "English" }
}

enum SectionItem: String, CaseIterable, Identifiable {
    case overview
    case dfu
    case info
    case library
    case downloads
    case restore
    case history
    case settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "house.fill"
        case .dfu: return "dot.radiowaves.left.and.right"
        case .info: return "info.circle.fill"
        case .library: return "books.vertical.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .restore: return "arrow.triangle.2.circlepath"
        case .history: return "clock.fill"
        case .settings: return "gearshape.fill"
        }
    }

    func title(_ language: AppLanguage) -> String {
        let ru = [
            "overview": "Обзор", "dfu": "Режим DFU", "info": "Устройство",
            "library": "Библиотека IPSW", "downloads": "Загрузки",
            "restore": "Восстановление", "history": "История", "settings": "Настройки"
        ]
        let en = [
            "overview": "Overview", "dfu": "DFU Mode", "info": "Device Info",
            "library": "IPSW Library", "downloads": "Downloads",
            "restore": "Recovery", "history": "History", "settings": "Settings"
        ]
        return (language == .russian ? ru : en)[rawValue] ?? rawValue
    }
}

struct DeviceInfo: Codable, Hashable, Identifiable {
    let type: String
    let ecid: String
    let mode: String

    var id: String { ecid }
    var maskedECID: String {
        guard ecid.count > 6 else { return ecid }
        return "••••" + ecid.suffix(6)
    }
}

struct FirmwareResponse: Codable {
    let name: String
    let identifier: String
    let firmwares: [Firmware]
}

struct Firmware: Codable, Identifiable, Hashable {
    let version: String
    let build: String
    let date: String
    let size: Int64
    let url: String
    let sha1: String
    let filename: String
    let beta: Bool?

    var id: String { build + url }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    var isBeta: Bool {
        if let beta { return beta }
        let marker = "\(version) \(build) \(filename)".lowercased()
        return marker.contains("beta") || marker.contains("seed") || marker.contains("release candidate")
    }
}

enum FirmwareSourceKind: String, Codable, CaseIterable, Identifiable {
    case ipswMe
    case ipswBeta
    case customURL
    case localCatalog
    case bundled

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.ipswMe, .russian): return "IPSW.me — онлайн-каталог"
        case (.ipswBeta, .russian): return "IPSWBeta.dev — beta-каталог"
        case (.customURL, .russian): return "Собственный HTTPS JSON"
        case (.localCatalog, .russian): return "Локальный JSON-каталог"
        case (.bundled, .russian): return "Встроенный каталог"
        case (.ipswMe, .english): return "IPSW.me — online catalog"
        case (.ipswBeta, .english): return "IPSWBeta.dev — beta catalog"
        case (.customURL, .english): return "Custom HTTPS JSON"
        case (.localCatalog, .english): return "Local JSON catalog"
        case (.bundled, .english): return "Bundled catalog"
        }
    }
}

struct ToolStatus: Codable, Equatable {
    let configuratorInstalled: Bool
    let configuratorPath: String
    let cfgutilInstalled: Bool
    let cfgutilPath: String
}

enum RecoveryKind: String, Codable, CaseIterable, Identifiable {
    case revive
    case restore

    // Revive remains decodable so that history from older versions can be read,
    // but the 4.3 user workflow intentionally exposes Restore only.
    static var allCases: [RecoveryKind] { [.restore] }

    var id: String { rawValue }
    var icon: String { self == .revive ? "heart.circle.fill" : "trash.circle.fill" }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.revive, .russian): return "Revive — сохранить данные"
        case (.restore, .russian): return "Restore — стереть данные"
        case (.revive, .english): return "Revive — preserve data"
        case (.restore, .english): return "Restore — erase data"
        }
    }
}

enum SessionPhase: String, Codable {
    case disconnected
    case detecting
    case connected
    case enteringDFU
    case downloading
    case validating
    case recovering
    case recoveryNeeded
    case completed
    case failed
}

struct HistoryRecord: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    var completedAt: Date?
    let operation: RecoveryKind
    let deviceType: String
    let maskedECID: String
    let firmwareVersion: String
    let firmwareBuild: String
    var result: String
    var detail: String
}

struct ResumeMetadata: Codable {
    let firmware: Firmware
    let destinationDirectory: String
    let createdAt: Date
}

enum DownloadPhase: Equatable {
    case idle
    case downloading
    case paused
    case validating
    case completed
    case failed(String)

    var isActive: Bool { self == .downloading || self == .validating }
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

enum L10n {
    static func text(_ ru: String, _ en: String, _ language: AppLanguage) -> String {
        language == .russian ? ru : en
    }
}
