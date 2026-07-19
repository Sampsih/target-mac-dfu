import Foundation

protocol BackendServing: AnyObject {
    var demoMode: Bool { get set }
    func run(_ arguments: [String], onOutput: ((String) -> Void)?) async throws -> String
}

final class BackendClient: BackendServing, @unchecked Sendable {
    var demoMode = false
    private let backendPath: String

    init() {
        let resources = ProcessInfo.processInfo.environment["TARGET_MAC_DFU_RESOURCES"]
            ?? Bundle.main.resourcePath
            ?? ""
        backendPath = resources + "/backend.zsh"
    }

    func run(_ arguments: [String], onOutput: ((String) -> Void)? = nil) async throws -> String {
        let path = backendPath
        let useDemo = demoMode
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let collector = ProcessOutputCollector(onOutput: onOutput)

                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = [path] + arguments
                var environment = ProcessInfo.processInfo.environment
                if useDemo { environment["TARGET_MAC_DFU_FAKE"] = "1" }
                process.environment = environment
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    collector.append(handle.availableData, isError: false)
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    collector.append(handle.availableData, isError: true)
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    collector.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), isError: false)
                    collector.append(stderrPipe.fileHandleForReading.readDataToEndOfFile(), isError: true)
                    let result = collector.snapshot()

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                        let fallback = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: NSError(
                            domain: "TargetMacDFU.Backend",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? fallback : message]
                        ))
                    }
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class ProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private let onOutput: ((String) -> Void)?

    init(onOutput: ((String) -> Void)?) { self.onOutput = onOutput }

    func append(_ data: Data, isError: Bool) {
        guard !data.isEmpty else { return }
        lock.lock()
        if isError { stderr.append(data) } else { stdout.append(data) }
        lock.unlock()
        if let text = String(data: data, encoding: .utf8), !text.isEmpty { onOutput?(text) }
    }

    func snapshot() -> (stdout: String, stderr: String) {
        lock.lock()
        defer { lock.unlock() }
        return (
            String(data: stdout, encoding: .utf8) ?? "",
            String(data: stderr, encoding: .utf8) ?? ""
        )
    }
}
