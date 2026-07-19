import Foundation
import CryptoKit

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var phase: DownloadPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var bytesWritten: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var speedBytesPerSecond: Double = 0
    @Published private(set) var activeFirmware: Firmware?
    @Published private(set) var completedURL: URL?

    var onCompletion: ((Result<URL, Error>) -> Void)?

    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private let context = DownloadContext()
    private var lastSampleDate = Date()
    private var lastSampleBytes: Int64 = 0
    private var demoTask: Task<Void, Never>?
    private var demoModeActive = false
    private let resumeDataURL: URL
    private let resumeMetadataURL: URL

    override private init() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Target Mac DFU", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        resumeDataURL = support.appendingPathComponent("download.resume")
        resumeMetadataURL = support.appendingPathComponent("download.json")
        super.init()
        let queue = OperationQueue()
        queue.name = "TargetMacDFU.DownloadDelegate"
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: .default, delegate: self, delegateQueue: queue)
        restorePausedDownload()
    }

    func start(firmware: Firmware, directory: URL, demo: Bool = false) {
        cancel(removeResumeData: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(firmware.filename)
        activeFirmware = firmware
        completedURL = nil
        progress = 0
        bytesWritten = 0
        totalBytes = firmware.size
        speedBytesPerSecond = 0
        context.configure(firmware: firmware, destination: destination)
        persistMetadata(firmware: firmware, directory: directory)

        if FileManager.default.fileExists(atPath: destination.path) {
            completedURL = destination
            progress = 1
            phase = .completed
            clearResumeFiles()
            onCompletion?(.success(destination))
            return
        }

        if demo {
            demoModeActive = true
            startDemoDownload(destination: destination, size: max(1, firmware.size))
            return
        }
        demoModeActive = false

        guard let url = URL(string: firmware.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            fail(AppError.message("Некорректный URL IPSW."))
            return
        }
        phase = .downloading
        lastSampleDate = Date()
        lastSampleBytes = 0
        task = session.downloadTask(with: url)
        task?.resume()
    }

    func pause() {
        guard phase == .downloading else { return }
        if let demoTask {
            demoTask.cancel()
            self.demoTask = nil
            phase = .paused
            return
        }
        context.setPausing(true)
        task?.cancel { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                if let data { try? data.write(to: self.resumeDataURL, options: .atomic) }
                self.task = nil
                self.phase = .paused
                self.context.setPausing(false)
            }
        }
    }

    func resume() {
        guard phase == .paused else { return }
        if demoModeActive, let firmware = activeFirmware, let destination = context.destination() {
            startDemoDownload(destination: destination, size: max(1, firmware.size))
            return
        }
        guard
              let data = try? Data(contentsOf: resumeDataURL),
              activeFirmware != nil else { return }
        phase = .downloading
        lastSampleDate = Date()
        lastSampleBytes = bytesWritten
        task = session.downloadTask(withResumeData: data)
        task?.resume()
    }

    func cancel(removeResumeData: Bool = true) {
        demoTask?.cancel()
        demoTask = nil
        demoModeActive = false
        task?.cancel()
        task = nil
        context.setPausing(false)
        if removeResumeData { clearResumeFiles() }
        if phase != .completed {
            phase = .idle
            progress = 0
            bytesWritten = 0
            speedBytesPerSecond = 0
            activeFirmware = nil
        }
    }

    func prepareForTermination(completion: @escaping () -> Void) {
        guard phase == .downloading, let task else { completion(); return }
        context.setPausing(true)
        task.cancel { [weak self] data in
            Task { @MainActor in
                if let self, let data { try? data.write(to: self.resumeDataURL, options: .atomic) }
                completion()
            }
        }
    }

    var progressText: String {
        let percent = Int((progress * 100).rounded())
        let written = ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)
        let total = totalBytes > 0
            ? ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            : "—"
        return "\(percent)% · \(written) / \(total)"
    }

    var speedText: String {
        guard speedBytesPerSecond > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(speedBytesPerSecond), countStyle: .file) + "/с"
    }

    private func startDemoDownload(destination: URL, size: Int64) {
        phase = .downloading
        demoTask = Task { [weak self] in
            for step in 1...100 {
                guard !Task.isCancelled, let self else { return }
                try? await Task.sleep(nanoseconds: 25_000_000)
                self.progress = Double(step) / 100
                self.totalBytes = size
                self.bytesWritten = Int64(Double(size) * self.progress)
                self.speedBytesPerSecond = Double(size) / 2.5
            }
            guard !Task.isCancelled, let self else { return }
            let data = Data(repeating: 0x54, count: Int(min(size, 10_000_000)))
            do {
                try data.write(to: destination, options: .atomic)
                self.complete(destination)
            } catch { self.fail(error) }
        }
    }

    private func restorePausedDownload() {
        guard let data = try? Data(contentsOf: resumeMetadataURL),
              let metadata = try? JSONDecoder.history.decode(ResumeMetadata.self, from: data),
              FileManager.default.fileExists(atPath: resumeDataURL.path) else { return }
        activeFirmware = metadata.firmware
        let destination = URL(fileURLWithPath: metadata.destinationDirectory, isDirectory: true)
            .appendingPathComponent(metadata.firmware.filename)
        context.configure(firmware: metadata.firmware, destination: destination)
        totalBytes = metadata.firmware.size
        phase = .paused
    }

    private func persistMetadata(firmware: Firmware, directory: URL) {
        let metadata = ResumeMetadata(
            firmware: firmware,
            destinationDirectory: directory.path,
            createdAt: Date()
        )
        if let data = try? JSONEncoder.history.encode(metadata) {
            try? data.write(to: resumeMetadataURL, options: .atomic)
        }
    }

    private func clearResumeFiles() {
        try? FileManager.default.removeItem(at: resumeDataURL)
        try? FileManager.default.removeItem(at: resumeMetadataURL)
    }

    private func complete(_ url: URL) {
        completedURL = url
        progress = 1
        bytesWritten = totalBytes > 0 ? totalBytes : bytesWritten
        speedBytesPerSecond = 0
        phase = .completed
        clearResumeFiles()
        CacheInspector.prune(
            directory: url.deletingLastPathComponent(),
            limitGB: AppSettings.shared.cacheLimitGB,
            excluding: url
        )
        onCompletion?(.success(url))
    }

    private func fail(_ error: Error) {
        phase = .failed(error.localizedDescription)
        speedBytesPerSecond = 0
        onCompletion?(.failure(error))
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastSampleDate)
            if elapsed >= 0.5 {
                self.speedBytesPerSecond = Double(totalBytesWritten - self.lastSampleBytes) / elapsed
                self.lastSampleDate = now
                self.lastSampleBytes = totalBytesWritten
            }
            self.bytesWritten = totalBytesWritten
            if totalBytesExpectedToWrite > 0 { self.totalBytes = totalBytesExpectedToWrite }
            let denominator = max(1, self.totalBytes)
            self.progress = min(1, Double(totalBytesWritten) / Double(denominator))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let destination = context.destination()
        var result: Result<URL, Error>
        if let destination {
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                result = .success(destination)
            } catch { result = .failure(error) }
        } else {
            result = .failure(AppError.message("Потеряна папка назначения загрузки."))
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch result {
            case .success(let url): self.complete(url)
            case .failure(let error): self.fail(error)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, !context.isPausing() else { return }
        Task { @MainActor [weak self] in self?.fail(error) }
    }
}

private final class DownloadContext: @unchecked Sendable {
    private let lock = NSLock()
    private var destinationURL: URL?
    private var pausing = false

    func configure(firmware: Firmware, destination: URL) {
        lock.lock(); destinationURL = destination; pausing = false; lock.unlock()
    }
    func destination() -> URL? { lock.lock(); defer { lock.unlock() }; return destinationURL }
    func setPausing(_ value: Bool) { lock.lock(); pausing = value; lock.unlock() }
    func isPausing() -> Bool { lock.lock(); defer { lock.unlock() }; return pausing }
}

enum IPSWValidator {
    static func validate(url: URL, firmware: Firmware) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.message("IPSW-файл не найден: \(url.path)")
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let actualSize = Int64(values.fileSize ?? 0)
        if firmware.size > 0, actualSize != firmware.size {
            throw AppError.message("Размер IPSW не совпадает с каталогом: \(actualSize) вместо \(firmware.size) байт.")
        }
        let expected = firmware.sha1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !expected.isEmpty {
            let actual = try sha1(url: url)
            guard actual == expected else {
                throw AppError.message("Контрольная сумма IPSW не совпадает. Файл нельзя использовать.")
            }
        }
    }

    private static func sha1(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while true {
            let data = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
