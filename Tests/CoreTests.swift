import Foundation

@main
struct CoreTests {
    @MainActor
    static func main() throws {
        try expect(UpdateChecker.isNewer("1.1.0", than: "1.0.9"), "semantic version upgrade")
        try expect(!UpdateChecker.isNewer("1.1.0", than: "1.1.0"), "equal semantic versions")
        try expect(!UpdateChecker.isNewer("1.0.9", than: "1.1.0"), "semantic version downgrade")

        _ = try IPSWValidator.validateDownloadURL("https://updates.cdn-apple.com/example.ipsw")
        do {
            _ = try IPSWValidator.validateDownloadURL("http://example.com/example.ipsw")
            throw TestFailure("insecure IPSW URL was accepted")
        } catch is TestFailure {
            throw TestFailure("insecure IPSW URL was accepted")
        } catch {
            // Expected.
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TargetMacDFUTests-\(UUID().uuidString)", isDirectory: true)
        let payload = root.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest: [String: Any] = [
            "SupportedProductTypes": ["Mac14,7"],
            "BuildIdentities": []
        ]
        let plist = try PropertyListSerialization.data(
            fromPropertyList: manifest,
            format: .binary,
            options: 0
        )
        try plist.write(to: payload.appendingPathComponent("BuildManifest.plist"))
        try Data("payload".utf8).write(to: payload.appendingPathComponent("dummy.bin"))

        let archive = root.appendingPathComponent("fixture.ipsw")
        try run("/usr/bin/zip", ["-q", "-r", archive.path, "."], directory: payload)
        let firmware = Firmware(
            version: "15.0",
            build: "24A000",
            date: "2026-01-01",
            size: 0,
            url: "https://updates.cdn-apple.com/fixture.ipsw",
            sha1: "",
            sha256: nil,
            filename: "fixture.ipsw",
            beta: false
        )
        let report = try IPSWValidator.validate(
            url: archive,
            firmware: firmware,
            expectedProductType: "Mac14,7"
        )
        try expect(report.productTypes == ["Mac14,7"], "BuildManifest compatibility")

        do {
            _ = try IPSWValidator.validate(
                url: archive,
                firmware: firmware,
                expectedProductType: "Mac99,1"
            )
            throw TestFailure("incompatible IPSW was accepted")
        } catch is TestFailure {
            throw TestFailure("incompatible IPSW was accepted")
        } catch {
            // Expected.
        }

        print("Core tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        if !condition() { throw TestFailure("Failed: \(name)") }
    }

    private static func run(_ executable: String, _ arguments: [String], directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw TestFailure("\(executable) failed with \(process.terminationStatus)")
        }
    }
}

private struct TestFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
