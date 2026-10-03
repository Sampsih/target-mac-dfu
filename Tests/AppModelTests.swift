import Foundation

@main
struct AppModelTests {
    @MainActor
    static func main() async throws {
        let backend = TestBackend()
        let model = AppModel(backend: backend, startMonitoring: false)
        model.device = DeviceInfo(type: "Mac14,7", ecid: "0x1234", mode: "DFU")
        model.dfuDetected = true
        model.selectedFirmware = Firmware(version: "15.0", build: "TEST", date: "", size: 0,
            url: "https://updates.cdn-apple.com/test.ipsw", sha1: "", sha256: nil,
            filename: "test-\(UUID().uuidString).ipsw", beta: false)
        let downloadPhase = model.downloads.phase

        model.requestRecovery()
        try expect(model.busy && model.preflightRunning && model.controlsLocked, "Restore request locks controls synchronously")
        model.requestRecovery()
        model.runPreflightNow()
        model.enterDFU()
        model.downloadOnly()
        model.refreshFirmwares()
        try await waitUntilIdle(model)
        try expect(backend.capabilityCalls == 1, "rapid clicks run one preflight only")
        try expect(backend.dfuCalls == 0 && backend.restoreCalls == 0, "blocked preflight never sends DFU or Restore")
        try expect(model.downloads.phase == downloadPhase, "blocked preflight never starts a download")
        try expect(!model.preflightReady && !model.controlsLocked && model.operations.current == nil, "failed preflight releases the gate")

        backend.changedDevice = true
        model.runPreflightNow()
        try await waitUntilIdle(model)
        try expect(model.preflightChecks.first { $0.id == "device" }?.state == .failed, "preflight detects changed ECID")

        backend.disconnected = true
        model.runPreflightNow()
        try await waitUntilIdle(model)
        try expect(model.preflightChecks.first { $0.id == "device" }?.state == .failed, "disconnected target fails preflight")
        try expect(!model.controlsLocked && backend.restoreCalls == 0, "connection failure releases the gate without Restore")

        model.sessionPhase = .completed
        model.status = "Completed"
        model.detail = "Next steps remain visible"
        let calls = backend.detectCalls
        await model.refreshDevice(silent: true)
        try expect(backend.detectCalls == calls && model.sessionPhase == .completed, "monitoring preserves completion guidance")
        model.sessionPhase = .recoveryNeeded
        await model.refreshDevice(silent: true)
        try expect(backend.detectCalls == calls && model.sessionPhase == .recoveryNeeded, "monitoring preserves recovery failure")

        for language in AppLanguage.allCases {
            try expect(!AppModel.completionDetail(for: "Mac14,7", language: language).isEmpty, "Apple silicon completion guidance")
            try expect(!AppModel.completionDetail(for: "MacBookPro16,1", language: language).isEmpty, "T2 completion guidance")
        }
        print("App model tests passed")
    }

    @MainActor
    private static func waitUntilIdle(_ model: AppModel) async throws {
        for _ in 0..<300 {
            if !model.busy { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw TestFailure("Operation did not release its gate")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        if !condition() { throw TestFailure(name) }
    }
}

private final class TestBackend: BackendServing, @unchecked Sendable {
    var demoMode = false
    var changedDevice = false
    var disconnected = false
    var capabilityCalls = 0
    var detectCalls = 0
    var dfuCalls = 0
    var restoreCalls = 0

    func run(_ arguments: [String], onOutput: ((String) -> Void)?) async throws -> String {
        switch arguments.first {
        case "capabilities":
            capabilityCalls += 1
            try await Task.sleep(nanoseconds: 30_000_000)
            return #"{"configuratorInstalled":true,"configuratorPath":"","cfgutilInstalled":false,"cfgutilPath":""}"#
        case "detect":
            detectCalls += 1
            if disconnected { throw NSError(domain: "TargetMacDFU.Backend", code: 6) }
            return changedDevice
                ? #"{"type":"Mac14,7","ecid":"0x5678","mode":"DFU"}"#
                : #"{"type":"Mac14,7","ecid":"0x1234","mode":"DFU"}"#
        case "dfu": dfuCalls += 1
        case "recover": restoreCalls += 1
        default: break
        }
        throw TestFailure("Unexpected backend command")
    }
}

private struct TestFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
