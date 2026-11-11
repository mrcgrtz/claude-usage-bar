# Changelog

All important changes to this project are in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.6] - 2026-11-11

### Added

- MIT License. The About window shows it.

## [0.5] - 2026-11-11

### Added

- **Check for Updates Automatically**: the app checks GitHub once a day, and the menu shows **Download Version …** when a new version is available.
- **Menu Bar** setting to choose the limits in the menu bar, and **Show** to show the percentage that is left.
- Rules can use the weekly limit of a single model.

### Fixed

- A rule that was inactive while its limit reset runs again when the usage reaches its threshold after you turn it on.

## [0.4] - 2026-11-11

### Added

- Rules: show a notification or run a shortcut when the 5-hour, weekly or extra usage reaches a threshold.
- **Settings…** window for the rules and **Launch at Login**.

### Changed

- **Launch at Login** moved from the menu to the Settings window.
- The weekly limit of a single model shows the name of the model, for example “Weekly (Fable)” instead of “weekly scoped”.

## [0.3] - 2026-11-11

### Added

- **Launch at Login** menu item.
- **About ClaudeUsageBar** menu item, which shows the version and a link to marcgoertz.de.
- German translation of the app and of its Internet Access Policy.

### Changed

- Reset times and extra usage amounts follow the time format, language and region of the Mac.
- Menu items use title-style capitalisation, as in other Mac apps.
- The menu bar shows a warning triangle instead of the gauge when the last update failed.

## [0.2] - 2026-11-11

### Added

- Internet Access Policy. Firewalls such as Little Snitch show why the app connects to `api.anthropic.com`.

## [0.1] - 2026-11-10

### Added

- Menu bar title with the 5-hour and weekly usage.
- Menu with all limits, reset times, extra usage and the last update time.
- Manual refresh and auto refresh every 5 to 60 minutes.
- Refresh after the Mac wakes from sleep.
- App icon.
- Universal app for Intel Macs and Macs with Apple silicon.
- Releases are a DMG file with an illustrated window. Drag the app to the `Applications` folder to install it.
- README with a screenshot, and changelog.
- SwiftLint check in GitHub Actions.

[Unreleased]: https://github.com/mrcgrtz/claude-usage-bar/compare/v0.6...main
[0.6]: https://github.com/mrcgrtz/claude-usage-bar/releases/tag/v0.6
[0.5]: https://github.com/mrcgrtz/claude-usage-bar/releases/tag/v0.5
[0.4]: https://github.com/mrcgrtz/claude-usage-bar/releases/tag/v0.4
[0.3]: https://github.com/mrcgrtz/claude-usage-bar/releases/tag/v0.3
[0.2]: https://github.com/mrcgrtz/claude-usage-bar/releases/tag/v0.2
[0.1]: https://github.com/mrcgrtz/claude-usage-bar/releases/tag/v0.1
