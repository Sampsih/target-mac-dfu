import Foundation
import Combine

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var lastCheckedAt: Date?

    private let endpoint = URL(string: "https://api.github.com/repos/Sampsih/target-mac-dfu/releases/latest")!

    func check(currentVersion: String) async {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue("Target-Mac-DFU/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw AppError.message("GitHub не вернул сведения о последнем релизе.")
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remote = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard let page = URL(string: release.htmlURL) else {
                throw AppError.message("Некорректная ссылка на релиз.")
            }
            lastCheckedAt = Date()
            state = Self.isNewer(remote, than: currentVersion)
                ? .available(version: remote, url: page)
                : .current
        } catch {
            lastCheckedAt = Date()
            state = .failed(error.localizedDescription)
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(candidate)
        let right = components(current)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { component in
                Int(component.prefix { $0.isNumber }) ?? 0
            }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
