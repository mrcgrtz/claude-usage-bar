import Foundation

// Tests of the app logic. ./test.sh compiles this file with the app code and runs it in English with
// US formats, so that the texts and numbers are the same on each Mac.

var failures = 0

@MainActor func expect<Value: Equatable>(_ got: Value, _ want: Value, _ name: String, line: Int = #line) {
    if got == want {
        print("ok    \(name)")
    } else {
        failures += 1
        print("FAIL  \(name) (line \(line)): got \(got), want \(want)")
    }
}

/// A usage response in the format of the API, with the values that a test needs.
func usage(session: Double = 0, weekly: Double = 0, fable: Double? = nil, spent: Double = 0) -> Usage? {
    let scoped = fable.map {
        #"{"kind":"weekly_scoped","percent":\#($0),"scope":{"model":{"id":null,"display_name":"Fable"}}},"#
    } ?? ""
    let json = """
        {"limits":[\(scoped)
          {"kind":"session","percent":\(session),"resets_at":"2026-11-11T05:00:00Z","scope":null},
          {"kind":"weekly_all","percent":\(weekly),"resets_at":"2026-11-14T22:20:00Z","scope":null}],
         "spend":{"enabled":true,"used":{"amount_minor":\(spent),"exponent":2,"currency":"USD"},
                  "limit":{"amount_minor":5000,"exponent":2,"currency":"USD"}}}
        """
    return try? JSONDecoder().decode(Usage.self, from: Data(json.utf8))
}

/// Settings that the tests can change without changing the settings of the app.
func testDefaults(_ name: String) -> UserDefaults {
    let suite = "ClaudeUsageBarTests.\(name)"
    UserDefaults.standard.removePersistentDomain(forName: suite)
    return UserDefaults(suiteName: suite)!
}

// MARK: - Rules

@MainActor func testRules() {
    let defaults = testDefaults("rules")
    var store = RuleStore(defaults: defaults)
    store.rules = [
        Rule(limit: .weekly, threshold: 80),
        Rule(limit: .session, threshold: 50),
        Rule(limit: .extra, threshold: 90)
    ]
    func due(_ usage: Usage?) -> [String] {
        guard let usage else { return ["invalid usage"] }
        return store.check(usage).map { "\($0.rule.limit.rawValue)@\(Int($0.percent))" }
    }

    expect(due(usage(session: 10, weekly: 70)), [], "no rule runs below its threshold")
    expect(due(usage(session: 55, weekly: 81)), ["weekly_all@81", "session@55"], "rules run at their threshold")
    expect(due(usage(session: 60, weekly: 85)), [], "a rule does not run again while the usage stays above")
    store = RuleStore(defaults: defaults)
    expect(due(usage(session: 60, weekly: 85)), [], "a rule does not run again after a relaunch")
    expect(due(usage(session: 2, weekly: 86)), [], "no rule runs when a limit resets")
    expect(due(usage(session: 51, weekly: 87)), ["session@51"], "a rule runs again after a reset")
    store.rules[0].threshold = 85
    expect(due(usage(session: 51, weekly: 87)), ["weekly_all@87"], "a changed threshold runs again")
    expect(due(usage(session: 51, weekly: 87, spent: 4600)), ["extra@92"], "extra usage is a percentage of the cap")
    store.rules[1].isEnabled = false
    expect(due(usage(session: 1, weekly: 87)), [], "an inactive rule does not run")
    expect(due(usage(session: 70, weekly: 87)), [], "an inactive rule does not run above its threshold")
    store.rules[1].isEnabled = true
    expect(due(usage(session: 70, weekly: 87)), ["session@70"], "an active rule runs again")

    let fable = RuleStore(defaults: testDefaults("fable"))
    fable.rules = [Rule(limit: .weeklyScoped, threshold: 50)]
    expect(fable.check(usage(fable: 50)!).map(\.percent), [50], "a rule can use the weekly limit of one model")

    store.rules.removeAll()
    expect(RuleStore(defaults: defaults).rules, [], "the rules are saved")
}

@MainActor func testRuleSummary() {
    expect(Rule(limit: .weekly, threshold: 80, notify: true).summary, "Weekly at 80% – Notification", "summary")
    let both = Rule(limit: .session, threshold: 95, notify: true, shortcut: Shortcut(id: "X", name: "Focus"))
    expect(both.summary, "5-hour at 95% – Notification and Shortcut “Focus”", "summary with two actions")
    expect(Rule(limit: .extra, threshold: 50, notify: false).summary, "Extra usage at 50% – No action",
           "summary without actions")
}

// MARK: - Usage

@MainActor func testLabels() {
    let json = """
        {"limits":[
          {"kind":"session","percent":26},
          {"kind":"weekly_all","percent":13},
          {"kind":"weekly_scoped","percent":0,"scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}},
          {"kind":"weekly_scoped","percent":4,"scope":{"model":null,"surface":null}},
          {"kind":"weekly_scoped","percent":5,"scope":"a new format"},
          {"kind":"monthly_thing","percent":1}
        ], "spend":null}
        """
    let limits = (try? JSONDecoder().decode(Usage.self, from: Data(json.utf8)))?.limits ?? []
    expect(limits.map(\.label), [
        "5-hour", "Weekly", "Weekly (Fable)", "Weekly (scoped)", "Weekly (scoped)", "monthly thing"
    ], "labels of the limits, also for a scope in a new format")
}

@MainActor func testMoney() {
    let usage = usage(spent: 1250)
    expect(usage?.spend?.used?.formatted, "$12.50", "an amount in the currency format of the region")
    expect(usage?.percent(.extra), 25, "the extra usage in percent")
}

// MARK: - Menu bar

@MainActor func testMenuBar() {
    let defaults = testDefaults("menubar")
    MenuBar.registerDefaults(defaults)
    let data = usage(session: 42, weekly: 18, fable: 7)!
    expect(MenuBar.title(data, defaults: defaults), "42% · 18%", "the 5-hour and weekly limits by default")
    expect(MenuBar.toolTip(defaults: defaults), "Claude usage: 5-hour · Weekly", "tooltip")
    defaults.set(true, forKey: MenuBar.key(.weeklyScoped))
    defaults.set(false, forKey: MenuBar.key(.session))
    expect(MenuBar.title(data, defaults: defaults), "18% · 7%", "the weekly limit of one model")
    defaults.set(true, forKey: MenuBar.showsLeftKey)
    expect(MenuBar.title(data, defaults: defaults), "82% · 93%", "the percentage that is left")
    expect(MenuBar.toolTip(defaults: defaults), "Claude usage left: Weekly · Weekly (single model)",
           "tooltip for the percentage that is left")
    expect(MenuBar.title(usage(weekly: 18)!, defaults: defaults), "82%", "a limit without data is left out")
    for limit in Rule.Limit.allCases {
        defaults.set(false, forKey: MenuBar.key(limit))
    }
    expect(MenuBar.title(data, defaults: defaults), "", "no values when no limit is chosen")
}

// MARK: - Updates

@MainActor func testUpdates() {
    expect(Updates.isNewer("0.5", than: "0.4"), true, "0.5 is newer than 0.4")
    expect(Updates.isNewer("0.10", than: "0.9"), true, "0.10 is newer than 0.9")
    expect(Updates.isNewer("1.0", than: "0.9.9"), true, "1.0 is newer than 0.9.9")
    expect(Updates.isNewer("0.4", than: "0.4"), false, "the same version is not newer")
    expect(Updates.isNewer("0.4", than: "0.4.0"), false, "0.4 and 0.4.0 are the same")
    expect(Updates.isNewer("0.3", than: "0.4"), false, "an older version is not newer")
    let release = try? JSONDecoder().decode(Updates.Release.self, from: Data(
        #"{"tag_name":"v0.5","html_url":"https://github.com/mrcgrtz/claude-usage-bar/releases/tag/v0.5"}"#.utf8
    ))
    expect(release?.version, "0.5", "the version of a release tag")
}

// MARK: - Shortcuts

@MainActor func testShortcuts() {
    let output = """
        Turn On Focus (C9BE8CB6-6335-4FA8-B6DB-BCB77FEF9DDD)
        Log (Usage) (0A9C7536-700B-46E2-87BA-5FDEC4C0EF1C)
        Not a shortcut line
        """
    let shortcuts = Shortcuts.parse(output)
    expect(shortcuts.map(\.name), ["Turn On Focus", "Log (Usage)"], "names of shortcuts, also with brackets")
    expect(shortcuts.first?.id, "C9BE8CB6-6335-4FA8-B6DB-BCB77FEF9DDD", "identifier of a shortcut")
}

testRules()
testRuleSummary()
testLabels()
testMoney()
testMenuBar()
testUpdates()
testShortcuts()
print(failures == 0 ? "All tests passed." : "\(failures) tests failed.")
exit(failures == 0 ? 0 : 1)
