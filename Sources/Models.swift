import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
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
        let titles: [AppLanguage: [String: String]] = [
            .russian: ["overview": "Обзор", "dfu": "Режим DFU", "info": "Устройство", "library": "Библиотека IPSW", "downloads": "Загрузки", "restore": "Восстановление", "history": "История", "settings": "Настройки"],
            .english: ["overview": "Overview", "dfu": "DFU Mode", "info": "Device", "library": "IPSW Library", "downloads": "Downloads", "restore": "Restore", "history": "History", "settings": "Settings"],
            .french: ["overview": "Aperçu", "dfu": "Mode DFU", "info": "Appareil", "library": "Bibliothèque IPSW", "downloads": "Téléchargements", "restore": "Restauration", "history": "Historique", "settings": "Réglages"],
            .german: ["overview": "Übersicht", "dfu": "DFU-Modus", "info": "Gerät", "library": "IPSW-Mediathek", "downloads": "Downloads", "restore": "Wiederherstellen", "history": "Verlauf", "settings": "Einstellungen"],
            .spanish: ["overview": "Resumen", "dfu": "Modo DFU", "info": "Dispositivo", "library": "Biblioteca IPSW", "downloads": "Descargas", "restore": "Restaurar", "history": "Historial", "settings": "Ajustes"]
        ]
        return titles[language]?[rawValue] ?? titles[.english]?[rawValue] ?? rawValue
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
    let sha256: String?
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
        let english: String
        switch self {
        case .ipswMe: english = "IPSW.me — online catalog"
        case .ipswBeta: english = "IPSWBeta.dev — beta catalog"
        case .customURL: english = "Custom HTTPS JSON"
        case .localCatalog: english = "Local JSON catalog"
        case .bundled: english = "Bundled catalog"
        }
        let russian: String
        switch self {
        case .ipswMe: russian = "IPSW.me — онлайн-каталог"
        case .ipswBeta: russian = "IPSWBeta.dev — beta-каталог"
        case .customURL: russian = "Собственный HTTPS JSON"
        case .localCatalog: russian = "Локальный JSON-каталог"
        case .bundled: russian = "Встроенный каталог"
        }
        return L10n.text(russian, english, language)
    }
}

struct ToolStatus: Codable, Equatable {
    let configuratorInstalled: Bool
    let configuratorPath: String
    let cfgutilInstalled: Bool
    let cfgutilPath: String
    let macvdmtoolInstalled: Bool?
    let macvdmtoolPath: String?
    let macvdmtoolRevision: String?
    let commandLineToolsInstalled: Bool?
    let hostArchitecture: String?
}

struct DFUPresence: Codable, Equatable {
    let detected: Bool
    let via: String
}

enum CheckState: String, Codable {
    case passed
    case warning
    case failed
    case pending

    var icon: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        case .pending: return "clock.fill"
        }
    }
}

struct PreflightCheck: Identifiable, Codable, Equatable {
    let id: String
    let state: CheckState
    let title: String
    let detail: String

    var blocksRestore: Bool { state == .failed || state == .pending }
}

struct IPSWValidationReport: Equatable {
    let fileSize: Int64
    let productTypes: [String]
    let hashKind: String?
    let hashValue: String?
    let warnings: [String]
}

enum UpdateState: Equatable {
    case idle
    case checking
    case current
    case available(version: String, url: URL)
    case failed(String)
}

enum RecoveryKind: String, Codable, CaseIterable, Identifiable {
    case revive
    case restore

    // Revive remains decodable so that history from older builds can be read,
    // but the public user workflow intentionally exposes Restore only.
    static var allCases: [RecoveryKind] { [.restore] }

    var id: String { rawValue }
    var icon: String { self == .revive ? "heart.circle.fill" : "trash.circle.fill" }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .revive: return L10n.text("Revive — сохранить данные", "Revive — preserve data", language)
        case .restore: return L10n.text("Restore — стереть данные", "Restore — erase data", language)
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
        switch language {
        case .russian: return ru
        case .english: return en
        case .french, .german, .spanish:
            return LocalizationCatalog.translation(for: en, language: language) ?? en
        }
    }

    static func text(
        _ ru: String,
        _ en: String,
        _ language: AppLanguage,
        replacing values: [String: String]
    ) -> String {
        values.reduce(into: text(ru, en, language)) { result, item in
            result = result.replacingOccurrences(of: "{\(item.key)}", with: item.value)
        }
    }
}
