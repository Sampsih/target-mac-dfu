import Foundation

@main
struct CoreTests {
    @MainActor
    static func main() throws {
        try expect(UpdateChecker.isNewer("1.1.0", than: "1.0.9"), "semantic version upgrade")
        try expect(!UpdateChecker.isNewer("1.1.0", than: "1.1.0"), "equal semantic versions")
        try expect(!UpdateChecker.isNewer("1.0.9", than: "1.1.0"), "semantic version downgrade")
        try expect(AppLanguage.allCases.count == 5, "five interface languages")
        let activity = TestActivity()
        let operations = OperationCoordinator(activity: activity)
        try expect(operations.begin(.preflight), "preflight acquires the gate synchronously")
        try expect(!operations.begin(.preflight), "duplicate preflight is blocked")
        try expect(!operations.begin(.enteringDFU), "overlapping DFU is blocked")
        try expect(!operations.protectsTermination && activity.started == 0, "preflight does not hold host activity")
        operations.transition(to: .restoring)
        try expect(operations.protectsTermination && activity.started == 1, "Restore protects quit and host sleep")
        operations.transition(to: .restoring)
        try expect(activity.started == 1, "repeated Restore transition does not leak activity tokens")
        operations.finish()
        operations.finish()
        try expect(activity.ended == 1 && operations.current == nil, "success or failure releases activity exactly once")
        try expect(operations.begin(.enteringDFU) && operations.protectsTermination, "DFU protects termination")
        operations.finish()
        try expect(activity.started == 2 && activity.ended == 2, "DFU cleanup releases host activity")
        try expect(operations.begin(.importingIPSW), "gate is reusable after failure cleanup")
        operations.finish()

        for model in ["MacBookPro15,1", "MacBookPro16,4", "MacBookAir9,1", "Macmini8,1", "iMac20,2", "iMacPro1,1", "MacPro7,1"] {
            try expect(DeviceInfo.isT2(model), "\(model) uses T2 completion guidance")
        }
        for model in ["Mac14,7", "MacBookPro17,1", "MacBookPro18,3", "MacBookAir10,1", "Macmini9,1", "iMac21,1"] {
            try expect(!DeviceInfo.isT2(model), "\(model) is not misclassified as T2")
        }
        try expect(WorkflowState.step(phase: .disconnected, dfuConfirmed: false, identified: false, firmwareReady: false) == 1, "connection step")
        try expect(WorkflowState.step(phase: .enteringDFU, dfuConfirmed: false, identified: false, firmwareReady: false) == 2, "DFU step is active")
        try expect(WorkflowState.step(phase: .connected, dfuConfirmed: true, identified: false, firmwareReady: false) == 2, "DFU without identity is not Restore-ready")
        try expect(WorkflowState.step(phase: .connected, dfuConfirmed: true, identified: true, firmwareReady: false) == 3, "firmware step")
        try expect(WorkflowState.step(phase: .connected, dfuConfirmed: true, identified: true, firmwareReady: true) == 4, "ready for Restore step")
        try expect(WorkflowState.step(phase: .completed, dfuConfirmed: false, identified: false, firmwareReady: false) == 4, "completed step stays visible")
        for language in [AppLanguage.french, .german, .spanish] {
            let safetyKeys = [
                "Wait for the operation to finish",
                "DFU or Restore is running. The app will stay open. Keep cable and power connected and leave the host Mac lid open.",
                "Multiple Macs connected",
                "Leave only one target Mac connected and check DFU again.",
                "DFU is not confirmed yet. Check the connection and try again.",
                "Wait for the operation to finish before clearing cache.",
                "Download canceled",
                "Restore has not started.",
                "Restore has not started: wait for the current operation to finish and check readiness again.",
                "The connected device changed. Select the Mac again before Restore.",
                "DFU and the selected ECID could not be confirmed. Check the connection and select the Mac again.",
                "Restore is complete. A T2 Mac may start Internet Recovery: connect to a network and install macOS. If Apple Account is requested, use the owner's account.",
                "Restore is complete. Follow the target Mac's onscreen instructions. If Apple Account is requested, use the owner's account, then complete Setup Assistant.",
                "All data on the target Mac will be erased. After Restore, follow its onscreen instructions; a T2 Mac may need macOS installation through Internet Recovery.",
                "Apple Instructions",
                "Step 2 of 4",
            ]
            try expect(LocalizationCatalog.coverage(for: language, keys: safetyKeys) == 1, "all new safety messages are translated for \(language.rawValue)")
            let settings = L10n.text("Настройки", "Settings", language)
            try expect(settings != "Settings", "\(language.rawValue) settings translation")
            let formatted = L10n.text(
                "Доступно IPSW: {count}",
                "Available IPSW: {count}",
                language,
                replacing: ["count": "3"]
            )
            try expect(formatted.contains("3") && !formatted.contains("{count}"), "\(language.rawValue) placeholder translation")
        }

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

@MainActor
private final class TestActivity: ActivityHolding {
    var started = 0
    var ended = 0
    func begin() -> NSObjectProtocol { started += 1; return NSObject() }
    func end(_ token: NSObjectProtocol) { ended += 1 }
}

private struct TestFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
