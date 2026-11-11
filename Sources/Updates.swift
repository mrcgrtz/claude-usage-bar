import Foundation

// MARK: - Updates

/// Checks GitHub for a newer release. The app has no automatic installer, so the menu links to the release.
enum Updates {
    static let enabledKey = "checkForUpdates"
    private static let latest = URL(string: "https://api.github.com/repos/mrcgrtz/claude-usage-bar/releases/latest")!

    struct Release: Decodable, Sendable {
        let tag_name: String
        let html_url: URL

        /// The tags have the form "v0.4".
        var version: String {
            tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name
        }
    }

    /// Returns the latest release when it is newer than the running app. A failed check returns nil,
    /// because the next check tries again.
    static func newerRelease(than version: String) async -> Release? {
        var request = URLRequest(url: latest)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (body, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: body),
              isNewer(release.version, than: version)
        else { return nil }
        return release
    }

    /// Compares the numbers of two versions, so that "0.10" is newer than "0.9".
    static func isNewer(_ version: String, than current: String) -> Bool {
        let new = version.split(separator: ".").map { Int($0) ?? 0 }
        let old = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(new.count, old.count) {
            let newPart = index < new.count ? new[index] : 0
            let oldPart = index < old.count ? old[index] : 0
            if newPart != oldPart {
                return newPart > oldPart
            }
        }
        return false
    }
}
