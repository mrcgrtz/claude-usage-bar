import Foundation

// MARK: - Menu bar

/// What the menu bar shows. The user chooses it in the General pane of the settings.
enum MenuBar {
    static let showsLeftKey = "menuBarShowsLeft"

    static func key(_ limit: Rule.Limit) -> String {
        "menuBar.\(limit.rawValue)"
    }

    /// The 5-hour and the weekly limit show by default, as in the versions before this setting.
    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        var values: [String: Any] = [showsLeftKey: false, Updates.enabledKey: true]
        for limit in Rule.Limit.allCases {
            values[key(limit)] = limit == .session || limit == .weekly
        }
        defaults.register(defaults: values)
    }

    private static func limits(_ defaults: UserDefaults) -> [Rule.Limit] {
        Rule.Limit.allCases.filter { defaults.bool(forKey: key($0)) }
    }

    /// The values in the menu bar, for example "42% · 18%". A limit without data is left out.
    static func title(_ usage: Usage, defaults: UserDefaults = .standard) -> String {
        let showsLeft = defaults.bool(forKey: showsLeftKey)
        return limits(defaults)
            .compactMap { usage.percent($0) }
            .map { (showsLeft ? max(0, 100 - $0) : $0).percentText }
            .joined(separator: " · ")
    }

    /// The tooltip says which limits the values are, for example "Claude usage: 5-hour · Weekly".
    static func toolTip(defaults: UserDefaults = .standard) -> String {
        let names = limits(defaults).map(\.name).joined(separator: " · ")
        if defaults.bool(forKey: showsLeftKey) {
            return String(localized: "Claude usage left: \(names)")
        }
        return String(localized: "Claude usage: \(names)")
    }
}
