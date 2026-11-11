# Changelog

All important changes to this project are in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Rules: show a notification or run a shortcut when the 5-hour, weekly or extra usage reaches a threshold.
- **Settings…** window for the rules and **Launch at Login**.

### Changed

- **Launch at Login** moved from the menu to the Settings window.

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

[Unreleased]: https://github.com/mrcgrtz/claude-usage-bar/compare/v0.3...main
[0.3]: https://github.com/mrcgrtz/claude-usage-bar/releases/tag/v0.3
[0.2]: https://github.com/mrcgrtz/claude-usage-bar/releases/tag/v0.2
[0.1]: https://github.com/mrcgrtz/claude-usage-bar/releases/tag/v0.1
