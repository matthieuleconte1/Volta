import AppKit
import Combine

/// Version of the running app ("dev" when not run from a bundle).
enum AppVersion {
    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
    static var build: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }

    /// Numeric components of a version tag: "v2.10.1" → [2, 10, 1].
    static func components(_ version: String) -> [Int] {
        let trimmed = version.hasPrefix("v") || version.hasPrefix("V") ? String(version.dropFirst()) : version
        return trimmed.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// Whether `candidate` is a newer version than `current` (missing components count as 0).
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Manual update check against the latest GitHub release (no dependency, nothing sent but the request itself).
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(version: String, url: URL)
        case failed
    }

    static let shared = UpdateChecker()
    private static let endpoint = URL(string: "https://api.github.com/repos/matthieuleconte1/Volta/releases/latest")!

    @Published private(set) var state: State = .idle

    func check() {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Volta", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let result = Self.parse(data: data, status: (response as? HTTPURLResponse)?.statusCode)
            DispatchQueue.main.async { self?.state = result }
        }.resume()
    }

    static func parse(data: Data?, status: Int?, current: String = AppVersion.current) -> State {
        guard status == 200, let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else { return .failed }
        let url = (json["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/matthieuleconte1/Volta/releases/latest")!
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return AppVersion.isNewer(tag, than: current) ? .available(version: version, url: url) : .upToDate
    }
}
