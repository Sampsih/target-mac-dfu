import Foundation
import CryptoKit

enum IPSWValidator {
    static func validate(url: URL, firmware: Firmware, expectedProductType: String? = nil) throws -> IPSWValidationReport {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.message("IPSW-файл не найден: \(url.path)")
        }
        guard url.pathExtension.lowercased() == "ipsw" else {
            throw AppError.message("Выбранный файл не имеет расширение .ipsw.")
        }

        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw AppError.message("IPSW должен быть обычным локальным файлом.")
        }
        let actualSize = Int64(values.fileSize ?? 0)
        guard actualSize > 4 else {
            throw AppError.message("IPSW-файл пуст или повреждён.")
        }
        if firmware.size > 0, actualSize != firmware.size {
            throw AppError.message("Размер IPSW не совпадает с каталогом: \(actualSize) вместо \(firmware.size) байт.")
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let magic = try handle.read(upToCount: 4) ?? Data()
        guard magic.count >= 2, magic[magic.startIndex] == 0x50, magic[magic.startIndex + 1] == 0x4B else {
            throw AppError.message("IPSW не является корректным ZIP-архивом.")
        }

        let entriesData = try run("/usr/bin/unzip", ["-Z1", url.path], maximumOutput: 8 * 1024 * 1024)
        guard let entriesText = String(data: entriesData, encoding: .utf8) else {
            throw AppError.message("Не удалось прочитать структуру IPSW.")
        }
        let manifestEntry = entriesText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0 == "BuildManifest.plist" || $0.hasSuffix("/BuildManifest.plist") }
        guard let manifestEntry else {
            throw AppError.message("В IPSW отсутствует BuildManifest.plist.")
        }

        let manifestData = try run(
            "/usr/bin/unzip",
            ["-p", url.path, manifestEntry],
            maximumOutput: 32 * 1024 * 1024
        )
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard
            let root = try PropertyListSerialization.propertyList(
                from: manifestData,
                options: [],
                format: &format
            ) as? [String: Any]
        else {
            throw AppError.message("BuildManifest.plist имеет неподдерживаемый формат.")
        }

        let productTypes = supportedProductTypes(in: root)
        if let expectedProductType, !productTypes.isEmpty {
            let matches = productTypes.contains {
                $0.caseInsensitiveCompare(expectedProductType) == .orderedSame
            }
            guard matches else {
                throw AppError.message(
                    "IPSW не предназначен для \(expectedProductType). В манифесте указаны: \(productTypes.joined(separator: ", "))."
                )
            }
        }

        let expectedSHA256 = firmware.sha256?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let expectedSHA1 = firmware.sha1
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        var hashKind: String?
        var hashValue: String?
        if !expectedSHA256.isEmpty {
            let actual = try digest(url: url, kind: .sha256)
            guard actual == expectedSHA256 else {
                throw AppError.message("Контрольная сумма SHA-256 IPSW не совпадает.")
            }
            hashKind = "SHA-256"
            hashValue = actual
        } else if !expectedSHA1.isEmpty {
            let actual = try digest(url: url, kind: .sha1)
            guard actual == expectedSHA1 else {
                throw AppError.message("Контрольная сумма SHA-1 IPSW не совпадает.")
            }
            hashKind = "SHA-1"
            hashValue = actual
        }

        var warnings: [String] = []
        if productTypes.isEmpty {
            warnings.append("BuildManifest не содержит явный список SupportedProductTypes.")
        }
        if hashKind == nil {
            warnings.append("Каталог не предоставил контрольную сумму; окончательную подпись проверят инструменты Apple.")
        }

        return IPSWValidationReport(
            fileSize: actualSize,
            productTypes: productTypes,
            hashKind: hashKind,
            hashValue: hashValue,
            warnings: warnings
        )
    }

    static func validateDownloadURL(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil else {
            throw AppError.message("IPSW можно загружать только по корректному HTTPS URL.")
        }
        return url
    }

    private static func supportedProductTypes(in root: [String: Any]) -> [String] {
        var values: [String] = []
        if let items = root["SupportedProductTypes"] as? [String] {
            values.append(contentsOf: items)
        }
        if let item = root["SupportedProductType"] as? String {
            values.append(item)
        }
        if let identities = root["BuildIdentities"] as? [[String: Any]] {
            for identity in identities {
                if let info = identity["Info"] as? [String: Any] {
                    if let item = info["ProductType"] as? String { values.append(item) }
                    if let items = info["SupportedProductTypes"] as? [String] { values.append(contentsOf: items) }
                }
            }
        }
        return Array(Set(values.filter { !$0.isEmpty })).sorted()
    }

    private enum DigestKind {
        case sha1
        case sha256
    }

    private static func digest(url: URL, kind: DigestKind) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha1 = Insecure.SHA1()
        var sha256 = SHA256()
        while true {
            let data = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            switch kind {
            case .sha1: sha1.update(data: data)
            case .sha256: sha256.update(data: data)
            }
        }
        switch kind {
        case .sha1:
            return sha1.finalize().map { String(format: "%02x", $0) }.joined()
        case .sha256:
            return sha256.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func run(_ executable: String, _ arguments: [String], maximumOutput: Int) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard data.count <= maximumOutput else {
            throw AppError.message("Служебные данные IPSW превышают допустимый размер.")
        }
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppError.message(detail?.isEmpty == false ? detail! : "Не удалось прочитать IPSW.")
        }
        return data
    }
}
