import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Settings window

/// A settings window with a toolbar of panes, as in Mail and other Mac apps.
@MainActor
enum SettingsWindow {
    static func make(store: RuleStore) -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(pane(String(localized: "General"), symbol: "gearshape", GeneralPane()))
        tabs.addTabViewItem(pane(String(localized: "Rules"), symbol: "checklist", RulesPane(store: store)))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }

    // The window takes the title of the pane, and resizes to the size of the pane.
    private static func pane(_ label: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

// MARK: - General

private struct GeneralPane: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(Updates.enabledKey) private var checkForUpdates = true
    @AppStorage(MenuBar.showsLeftKey) private var showsLeft = false

    var body: some View {
        // Group boxes with a title, as in the settings of other Mac apps.
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Startup and Updates") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { launchAtLogin },
                        set: { enabled in
                            LaunchAtLogin.set(enabled)
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    ))
                    Toggle("Check for Updates Automatically", isOn: $checkForUpdates)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox("Menu Bar") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("Limits")
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Rule.Limit.allCases) { MenuBarToggle(limit: $0) }
                        }
                    }
                    GridRow {
                        Text("Show")
                        Picker("Show", selection: $showsLeft) {
                            Text("Percent Used").tag(false)
                            Text("Percent Left").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
        .padding(20)
        .frame(width: 640, alignment: .leading)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
}

/// A checkbox that adds a limit to the menu bar.
private struct MenuBarToggle: View {
    let limit: Rule.Limit
    @AppStorage private var isOn: Bool

    init(limit: Rule.Limit) {
        self.limit = limit
        _isOn = AppStorage(wrappedValue: limit == .session || limit == .weekly, MenuBar.key(limit))
    }

    var body: some View {
        Toggle(limit.name, isOn: $isOn)
    }
}

// MARK: - Rules

private struct RulesPane: View {
    @ObservedObject var store: RuleStore
    @State private var selection: Rule.ID?
    @State private var editing: Rule?
    @State private var shortcuts: [Shortcut] = []

    private var selected: Rule? {
        store.rules.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Table(store.rules, selection: $selection) {
                    TableColumn("Active") { rule in
                        Toggle("Active", isOn: isEnabled(rule))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                    }
                    .width(44)
                    TableColumn("Description") { rule in
                        // The tooltip shows the whole description when the column cuts it off.
                        Text(rule.summary)
                            .help(rule.summary)
                    }
                }
                .contextMenu(forSelectionType: Rule.ID.self) { _ in
                } primaryAction: { ids in
                    editing = store.rules.first { ids.contains($0.id) }
                }
                .onDeleteCommand(perform: remove)

                VStack(spacing: 8) {
                    paneButton("Add Rule") { editing = Rule() }
                    paneButton("Edit") { editing = selected }
                        .disabled(selected == nil)
                    paneButton("Duplicate", action: duplicate)
                        .disabled(selected == nil)
                    paneButton("Remove", action: remove)
                        .disabled(selected == nil)
                }
                .frame(width: 130)
            }

            Text("""
                A rule runs once when the usage reaches its threshold. It runs again after the usage went \
                below the threshold, for example when the limit resets. The app checks the rules at each refresh.
                """)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 640, height: 360)
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, shortcuts: shortcuts, save: save)
        }
        .task { shortcuts = await Shortcuts.all() }
    }

    private func paneButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
    }

    private func isEnabled(_ rule: Rule) -> Binding<Bool> {
        Binding(
            get: { store.rules.first { $0.id == rule.id }?.isEnabled ?? false },
            set: { enabled in
                if let index = store.rules.firstIndex(where: { $0.id == rule.id }) {
                    store.rules[index].isEnabled = enabled
                }
            }
        )
    }

    private func save(_ rule: Rule) {
        if let index = store.rules.firstIndex(where: { $0.id == rule.id }) {
            store.rules[index] = rule
        } else {
            store.rules.append(rule)
        }
        selection = rule.id
        if rule.notify {
            Task { _ = await Notifications.requestPermission() }
        }
    }

    private func duplicate() {
        guard let rule = selected, let index = store.rules.firstIndex(of: rule) else { return }
        var copy = rule
        copy.id = UUID()
        store.rules.insert(copy, at: index + 1)
        selection = copy.id
    }

    private func remove() {
        store.rules.removeAll { $0.id == selection }
        selection = nil
    }
}

/// The sheet that adds or edits a rule. The changes apply only when the user clicks OK.
struct RuleEditor: View {
    @State private var rule: Rule
    /// Starts with the shortcuts that the pane loaded, and loads them again when the sheet opens.
    /// A sheet keeps the values that it opened with, and the user can add shortcuts while the window is open.
    @State private var shortcuts: [Shortcut]
    let save: (Rule) -> Void
    @Environment(\.dismiss) private var dismiss

    init(rule: Rule, shortcuts: [Shortcut], save: @escaping (Rule) -> Void) {
        _rule = State(initialValue: rule)
        _shortcuts = State(initialValue: shortcuts)
        self.save = save
    }

    /// The shortcut of the rule stays in the list when the user deleted it or the list is still loading.
    private var choices: [Shortcut] {
        guard let current = rule.shortcut, !shortcuts.contains(current) else { return shortcuts }
        return [current] + shortcuts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Form {
                Picker("Limit:", selection: $rule.limit) {
                    ForEach(Rule.Limit.allCases) { Text($0.name).tag($0) }
                }
                LabeledContent("Threshold:") {
                    HStack {
                        Text(Double(rule.threshold).percentText)
                            .monospacedDigit()
                        Stepper("Threshold:", value: $rule.threshold, in: 5...100, step: 5)
                            .labelsHidden()
                    }
                }
                Toggle("Show Notification", isOn: $rule.notify)
                Picker("Run Shortcut:", selection: $rule.shortcut) {
                    Text("None").tag(Shortcut?.none)
                    ForEach(choices) { Text($0.name).tag(Shortcut?.some($0)) }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    save(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .task { shortcuts = await Shortcuts.all() }
    }
}

// MARK: - Launch at login

@MainActor
enum LaunchAtLogin {
    static func set(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch where service.status != .requiresApproval {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = String(localized: "Launch at Login could not be changed.")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        } catch {}
        // When the user turned the app off in Login Items, only System Settings can turn it on again.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
