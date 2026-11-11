import AppKit
import ServiceManagement

// MARK: - Usage API model

struct Usage: Decodable {
    let limits: [Limit]
    let spend: Spend?

    struct Limit: Decodable {
        let kind: String
        let percent: Double?
        let resets_at: String?
    }

    struct Spend: Decodable {
        let enabled: Bool?
        let used: Money?
        let limit: Money?
    }

    struct Money: Decodable {
        let amount_minor: Double
        let exponent: Int
        let currency: String?

        var formatted: String {
            let amount = amount_minor / pow(10, Double(exponent))
            guard let currency else {
                return amount.formatted(.number.precision(.fractionLength(exponent)))
            }
            return amount.formatted(.currency(code: currency).precision(.fractionLength(exponent)))
        }
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settingsKey = "refreshMinutes"
    private let refreshOptions = [5, 10, 20, 30, 60]
    private let labels = ["session": "5-hour", "weekly_all": "Weekly"]

    private var item: NSStatusItem!
    private var usage: Usage?
    private var errorMessage: String?
    private var lastUpdated: String?
    private var inFlight = false
    private var timer: Timer?

    private var refreshMinutes: Int {
        UserDefaults.standard.object(forKey: settingsKey) as? Int ?? 30
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A fixed autosave name gives the menu bar item the same identity at each launch.
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "ClaudeUsageBar"
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

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
    }

    // Template mode lets macOS tint the icon for light and dark menu bars.
    private static func icon(warning: Bool = false) -> NSImage? {
        let gauge = "gauge.with.dots.needle.67percent"
        let warningSymbol = "exclamationmark.triangle"
        let image = warning
            ? NSImage(systemSymbolName: warningSymbol, accessibilityDescription: "Error")
            : Bundle.main.image(forResource: "claude-icon")
                ?? NSImage(systemSymbolName: gauge, accessibilityDescription: "Claude usage")
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }

    // MARK: Title

    private func limit(_ kind: String) -> Usage.Limit? {
        usage?.limits.first { $0.kind == kind }
    }

    private func used(_ limit: Usage.Limit?) -> String {
        guard let percent = limit?.percent else { return "N/A" }
        return "\(Int(percent.rounded()))%"
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
        item.button?.toolTip = errorMessage ?? "Claude usage: 5-hour · weekly"
    }

    // MARK: Fetch

    private func finish(_ message: String?, _ data: Usage? = nil) {
        inFlight = false
        errorMessage = message
        if let data {
            usage = data
            lastUpdated = Date().formatted(date: .omitted, time: .shortened)
        }
        updateTitle()
    }

    private func refresh() {
        guard !inFlight else { return }
        inFlight = true
        Task {
            guard let token = await Self.readToken() else {
                return finish("Claude Code Keychain credentials unavailable")
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
                return finish("Token expired - run claude to refresh it")
            }
            if status != 200 {
                return finish("Usage API returned HTTP \(status)")
            }
            guard let data = try? JSONDecoder().decode(Usage.self, from: body) else {
                return finish("Invalid usage response")
            }
            finish(nil, data)
        } catch {
            finish("Usage API request failed: \(error.localizedDescription)")
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
                title: minutes == 0 ? "Off" : "Every \(minutes) Minutes",
                action: #selector(selectAutoRefresh(_:)), keyEquivalent: ""
            )
            entry.target = self
            entry.tag = minutes
            entry.state = refreshMinutes == minutes ? .on : .off
            menu.addItem(entry)
        }
        return menu
    }

    // MARK: Launch at login

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch where service.status != .requiresApproval {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Launch at Login could not be changed."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        } catch {}
        // When the user turned the app off in Login Items, only System Settings can turn it on again.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
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
            return "unknown"
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let usage {
            for limit in usage.limits {
                let label = labels[limit.kind] ?? limit.kind.replacingOccurrences(of: "_", with: " ")
                addInfo(menu, "\(label): \(used(limit)) used, resets \(resetTime(limit.resets_at))")
            }
            if let spend = usage.spend, spend.enabled == true, let spent = spend.used, let cap = spend.limit {
                addInfo(menu, "Extra usage: \(spent.formatted) / \(cap.formatted)")
            }
            menu.addItem(.separator())
            addInfo(menu, "Updated: \(lastUpdated ?? "-")")
        }
        if let errorMessage {
            addInfo(menu, errorMessage)
        }
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let autoItem = NSMenuItem(title: "Auto Refresh", action: nil, keyEquivalent: "")
        autoItem.submenu = autoRefreshMenu()
        menu.addItem(autoItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About ClaudeUsageBar", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let quit = #selector(NSApplication.terminate(_:))
        menu.addItem(NSMenuItem(title: "Quit ClaudeUsageBar", action: quit, keyEquivalent: "q"))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
