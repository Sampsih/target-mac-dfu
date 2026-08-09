import Foundation

enum LocalizationCatalog {
    private static let table: [String: [String: String]] = load()

    static func translation(for english: String, language: AppLanguage) -> String? {
        guard language != .english, language != .russian else { return nil }
        return table[language.rawValue]?[english]
    }

    static func coverage(for language: AppLanguage, keys: [String]) -> Double {
        guard !keys.isEmpty else { return 1 }
        let translated = keys.reduce(into: 0) { count, key in
            if table[language.rawValue]?[key]?.isEmpty == false { count += 1 }
        }
        return Double(translated) / Double(keys.count)
    }

    private static func load() -> [String: [String: String]] {
        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
                continue
            }
            return decoded
        }
        return [:]
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("localizations.json") {
            urls.append(bundled)
        }
        if let root = ProcessInfo.processInfo.environment["TARGET_MAC_DFU_RESOURCES"] {
            urls.append(URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("localizations.json"))
        }
        urls.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Resources/localizations.json")
        )
        return urls
    }
}
