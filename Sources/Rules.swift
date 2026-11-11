import Foundation
import UserNotifications

// MARK: - Rules

/// A rule shows a notification or runs a shortcut when the usage of a limit reaches a threshold.
struct Rule: Codable, Identifiable, Equatable {
    /// The limits that rules and the menu bar can use.
    enum Limit: String, Codable, CaseIterable, Identifiable {
        case session
        case weekly = "weekly_all"
        /// The weekly limit of one model. The menu shows the name of the model, for example "Weekly (Fable)".
        case weeklyScoped = "weekly_scoped"
        case extra

        var id: Self { self }

        var name: String {
            switch self {
            case .session: String(localized: "5-hour")
            case .weekly: String(localized: "Weekly")
            case .weeklyScoped: String(localized: "Weekly (single model)")
            case .extra: String(localized: "Extra usage")
            }
        }
    }

    var id = UUID()
    var isEnabled = true
    var limit = Limit.weekly
    var threshold = 80
    var notify = true
    var shortcut: Shortcut?

    /// The description in the list of rules, for example "Weekly at 80 % – Notification and Shortcut “Focus”".
    var summary: String {
        var actions: [String] = []
        if notify {
            actions.append(String(localized: "Notification"))
        }
        if let shortcut {
            actions.append(String(localized: "Shortcut “\(shortcut.name)”"))
        }
        let list = actions.isEmpty ? String(localized: "No action") : actions.formatted(.list(type: .and))
        return String(localized: "\(limit.name) at \(Double(threshold).percentText) – \(list)")
    }
}

/// The input that a shortcut gets as a JSON file.
struct RuleInput: Encodable {
    let limit: String
    let percent: Double
    let threshold: Int
    let resetsAt: String?
}

@MainActor
final class RuleStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var rules: [Rule] {
        didSet { defaults.set(try? JSONEncoder().encode(rules), forKey: "rules") }
    }

    /// The rules that ran and wait for the usage to go below their threshold.
    /// The key changes when the user changes the limit or the threshold, so that the rule can run again.
    private var fired: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rules = defaults.data(forKey: "rules").flatMap { try? JSONDecoder().decode([Rule].self, from: $0) } ?? []
        fired = Set(defaults.stringArray(forKey: "firedRules") ?? [])
    }

    private static func key(_ rule: Rule) -> String {
        "\(rule.id.uuidString)-\(rule.limit.rawValue)-\(rule.threshold)"
    }

    /// Returns the rules that reached their threshold since the last check. Each rule runs once,
    /// and again only after the usage went below the threshold, for example when the limit resets.
    func check(_ usage: Usage) -> [(rule: Rule, percent: Double)] {
        var due: [(rule: Rule, percent: Double)] = []
        for rule in rules {
            guard let percent = usage.percent(rule.limit) else { continue }
            let key = Self.key(rule)
            // An inactive rule does not run, but it still sees the usage go below its threshold.
            // Otherwise it would not run after the user turns it on again.
            if percent < Double(rule.threshold) {
                fired.remove(key)
            } else if rule.isEnabled, fired.insert(key).inserted {
                due.append((rule, percent))
            }
        }
        // Forget the rules that the user removed or changed.
        fired.formIntersection(rules.map(Self.key))
        defaults.set(Array(fired), forKey: "firedRules")
        return due
    }
}

// MARK: - Shortcuts

struct Shortcut: Codable, Hashable, Identifiable {
    /// The identifier keeps the rule working when the user renames the shortcut.
    let id: String
    let name: String
}

enum Shortcuts {
    /// The shortcuts of the user.
    static func all() async -> [Shortcut] {
        parse(await shortcuts(["list", "--show-identifiers"]).output)
    }

    /// The shortcuts command prints each shortcut as "Name (identifier)".
    static func parse(_ output: String) -> [Shortcut] {
        output.split(separator: "\n").compactMap { line in
            guard line.hasSuffix(")"), let open = line.range(of: " (", options: .backwards) else { return nil }
            let id = line[open.upperBound..<line.index(before: line.endIndex)]
            return Shortcut(id: String(id), name: String(line[..<open.lowerBound]))
        }
    }

    /// Runs a shortcut with a JSON file as its input. Returns an error message when the shortcut fails.
    static func run(_ shortcut: Shortcut, input: RuleInput) async -> String? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeUsageBar-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try JSONEncoder().encode(input).write(to: url)
        } catch {
            return error.localizedDescription
        }
        let result = await shortcuts(["run", shortcut.id, "--input-path", url.path])
        guard result.status != 0 else { return nil }
        // The shortcuts command starts its messages with "Error: ", but the menu already says that the shortcut failed.
        let message = result.errors.replacingOccurrences(of: "Error: ", with: "", options: .anchored)
        return message.isEmpty ? "exit status \(result.status)" : message
    }

    private struct Result: Sendable {
        let status: Int32
        let output: String
        let errors: String
    }

    private static func shortcuts(_ arguments: [String]) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors
            process.terminationHandler = { process in
                let text = { (pipe: Pipe) in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                continuation.resume(returning: Result(
                    status: process.terminationStatus, output: text(output), errors: text(errors)
                ))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: Result(status: -1, output: "", errors: error.localizedDescription))
            }
        }
    }
}

// MARK: - Notifications

enum Notifications {
    /// macOS asks the user the first time. Returns false when the user turned notifications off.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Returns an error message when macOS does not show the notification.
    static func post(title: String, body: String) async -> String? {
        guard await requestPermission() else {
            return String(
                localized: "Notifications are off for ClaudeUsageBar. Turn them on in System Settings → Notifications."
            )
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
