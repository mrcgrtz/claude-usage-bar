import AppKit
import SwiftUI
import UserNotifications

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let settingsKey = "refreshMinutes"
    private let refreshOptions = [5, 10, 20, 30, 60]

    private var item: NSStatusItem!
    private var usage: Usage?
    private var errorMessage: String?
    private var lastUpdated: String?
    private var inFlight = false
    private var timer: Timer?
    private let rules = RuleStore()
    private var ruleError: String?
    private var settingsWindow: NSWindow?
    private var update: Updates.Release?
    private var updateTimer: Timer?

    private var refreshMinutes: Int {
        UserDefaults.standard.object(forKey: settingsKey) as? Int ?? 30
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Updates.enabledKey: true])
        // A fixed autosave name gives the menu bar item the same identity at each launch.
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "ClaudeUsageBar"
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        UNUserNotificationCenter.current().delegate = self

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.refreshMinutes > 0 else { return }
                // Give Wi-Fi time to reconnect before the app calls the API.
                Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
                    MainActor.assumeIsolated { self.refresh() }
                }
            }
        }

        updateTitle()
        refresh()
        setAutoRefresh(refreshMinutes)
        startUpdateChecks()
    }

    // Template mode lets macOS tint the icon for light and dark menu bars.
    private static func icon(warning: Bool = false) -> NSImage? {
        let gauge = "gauge.with.dots.needle.67percent"
        let warningSymbol = "exclamationmark.triangle"
        let image = warning
            ? NSImage(systemSymbolName: warningSymbol, accessibilityDescription: String(localized: "Error"))
            : Bundle.main.image(forResource: "claude-icon")
                ?? NSImage(systemSymbolName: gauge, accessibilityDescription: String(localized: "Claude usage"))
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }

    // MARK: Title

    private func limit(_ kind: String) -> Usage.Limit? {
        usage?.limits.first { $0.kind == kind }
    }

    private func used(_ limit: Usage.Limit?) -> String {
        guard let percent = limit?.percent else { return String(localized: "N/A") }
        return percent.percentText
    }

    private func updateTitle() {
        let title: String
        if usage != nil {
            title = " \(used(limit("session"))) · \(used(limit("weekly_all")))"
        } else {
            title = errorMessage != nil ? "" : " …"
        }
        item.button?.image = Self.icon(warning: errorMessage != nil)
        item.button?.title = title
        item.button?.toolTip = errorMessage ?? String(localized: "Claude usage: 5-hour · weekly")
    }

    // MARK: Fetch

    private func finish(_ message: String?, _ data: Usage? = nil) {
        inFlight = false
        errorMessage = message
        if let data {
            usage = data
            lastUpdated = Date().formatted(date: .omitted, time: .shortened)
            runRules(data)
        }
        updateTitle()
    }

    private func refresh() {
        guard !inFlight else { return }
        inFlight = true
        Task {
            guard let token = await Self.readToken() else {
                return finish(String(localized: "Claude Code Keychain credentials unavailable"))
            }
            await fetch(token)
        }
    }

    // The security CLI reads the item that Claude Code wrote, as the Hammerspoon version did.
    private nonisolated static func readToken() async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let oauth = json?["claudeAiOauth"] as? [String: Any]
                continuation.resume(returning: oauth?["accessToken"] as? String)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func fetch(_ token: String) async {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                return finish(String(localized: "Token expired - run claude to refresh it"))
            }
            if status != 200 {
                return finish(String(localized: "Usage API returned HTTP \(status)"))
            }
            guard let data = try? JSONDecoder().decode(Usage.self, from: body) else {
                return finish(String(localized: "Invalid usage response"))
            }
            finish(nil, data)
        } catch {
            finish(String(localized: "Usage API request failed: \(error.localizedDescription)"))
        }
    }

    // MARK: Auto refresh

    private func setAutoRefresh(_ minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: settingsKey)
        timer?.invalidate()
        timer = nil
        if minutes > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    @objc private func refreshNow() { refresh() }

    @objc private func selectAutoRefresh(_ sender: NSMenuItem) { setAutoRefresh(sender.tag) }

    private func autoRefreshMenu() -> NSMenu {
        let menu = NSMenu()
        for minutes in [0] + refreshOptions {
            let entry = NSMenuItem(
                title: minutes == 0 ? String(localized: "Off") : String(localized: "Every \(minutes) Minutes"),
                action: #selector(selectAutoRefresh(_:)), keyEquivalent: ""
            )
            entry.target = self
            entry.tag = minutes
            entry.state = refreshMinutes == minutes ? .on : .off
            menu.addItem(entry)
        }
        return menu
    }

    // MARK: About

    // The app has no windows of its own, so it must come to the front for the About window.
    @objc private func showAbout() {
        NSApp.activate()
        // The credits show below the copyright, as a link to the website of the developer.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(string: "marcgoertz.de", attributes: [
            .link: URL(string: "https://marcgoertz.de")!,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .paragraphStyle: paragraph
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: Menu

    private static let isoParsers: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [fractional, ISO8601DateFormatter()]
    }()

    private func resetTime(_ iso: String?) -> String {
        guard let iso, let date = Self.isoParsers.lazy.compactMap({ $0.date(from: iso) }).first else {
            return String(localized: "unknown")
        }
        // The format style follows the 12- or 24-hour setting and the language of the Mac.
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func addInfo(_ menu: NSMenu, _ title: String) {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        menu.addItem(entry)
    }

    @discardableResult
    private func addAction(_ menu: NSMenu, _ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let usage {
            for limit in usage.limits {
                let label = limit.label
                addInfo(menu, String(localized: "\(label): \(used(limit)) used, resets \(resetTime(limit.resets_at))"))
            }
            if let spend = usage.spend, spend.enabled == true, let spent = spend.used, let cap = spend.limit {
                addInfo(menu, String(localized: "Extra usage: \(spent.formatted) / \(cap.formatted)"))
            }
            menu.addItem(.separator())
            addInfo(menu, String(localized: "Updated: \(lastUpdated ?? "-")"))
        }
        if let errorMessage {
            addInfo(menu, errorMessage)
        }
        if let ruleError {
            addInfo(menu, ruleError)
        }
        menu.addItem(.separator())

        if let update {
            addAction(menu, String(localized: "Download Version \(update.version)…"), #selector(openUpdate))
            menu.addItem(.separator())
        }
        addAction(menu, String(localized: "Refresh Now"), #selector(refreshNow), key: "r")
        addAction(menu, String(localized: "Auto Refresh"), nil).submenu = autoRefreshMenu()

        menu.addItem(.separator())
        addAction(menu, String(localized: "Settings…"), #selector(showSettings), key: ",")
        addAction(menu, String(localized: "About ClaudeUsageBar"), #selector(showAbout))
        // Quit goes to NSApplication, not to this delegate.
        let quit = #selector(NSApplication.terminate(_:))
        menu.addItem(NSMenuItem(title: String(localized: "Quit ClaudeUsageBar"), action: quit, keyEquivalent: "q"))
    }
}

// MARK: - Rules and settings

extension AppDelegate {
    // MARK: Rules

    private func runRules(_ usage: Usage) {
        for (rule, percent) in rules.check(usage) {
            Task { await runActions(rule, percent: percent, usage: usage) }
        }
    }

    private func runActions(_ rule: Rule, percent: Double, usage: Usage) async {
        var errors: [String] = []
        if rule.notify {
            let title = String(localized: "\(rule.limit.name): \(Double(rule.threshold).percentText) reached")
            if let error = await Notifications.post(title: title, body: summary(rule.limit, usage)) {
                errors.append(error)
            }
        }
        if let shortcut = rule.shortcut {
            let resetsAt = usage.limits.first { $0.kind == rule.limit.rawValue }?.resets_at
            let input = RuleInput(
                limit: rule.limit.rawValue, percent: percent, threshold: rule.threshold, resetsAt: resetsAt
            )
            if let error = await Shortcuts.run(shortcut, input: input) {
                errors.append(String(localized: "Shortcut “\(shortcut.name)” failed: \(error)"))
            }
        }
        ruleError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    /// The same text as the row of the limit in the menu.
    private func summary(_ limit: Rule.Limit, _ usage: Usage) -> String {
        if limit == .extra, let spent = usage.spend?.used, let cap = usage.spend?.limit {
            return String(localized: "Extra usage: \(spent.formatted) / \(cap.formatted)")
        }
        let entry = usage.limits.first { $0.kind == limit.rawValue }
        return String(localized: "\(limit.name): \(used(entry)) used, resets \(resetTime(entry?.resets_at))")
    }

    // Without this, macOS hides notifications while the app is in front, for example with the Settings window open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // MARK: Updates

    private func startUpdateChecks() {
        checkForUpdates()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdates() }
        }
    }

    private func checkForUpdates() {
        guard UserDefaults.standard.bool(forKey: Updates.enabledKey) else {
            update = nil
            return
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        Task { update = await Updates.newerRelease(than: version) }
    }

    @objc private func openUpdate() {
        if let update {
            NSWorkspace.shared.open(update.html_url)
        }
    }

    // MARK: Settings

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow.make(store: rules)
            settingsWindow?.center()
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
