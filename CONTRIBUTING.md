# Contributing

This file tells you how to change ClaudeUsageBar. For what the app does and how to install it, read the [README](README.md).

## Requirements

- macOS 14 or later.
- The Xcode Command Line Tools. Run `xcode-select --install` to get them. You do not need the full Xcode app.
- [Claude Code](https://claude.com/claude-code), logged in. The app reads its login token, so you need it to test the app.
- [SwiftLint](https://github.com/realm/SwiftLint) 0.57.0. CI uses this version. Run `brew install swiftlint` to get it, or use Docker (see [Lint](#lint)).

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/main.swift` | The menu bar item, the menu and the requests to the usage API. |
| `Sources/Usage.swift` | The data of the usage API. |
| `Sources/Rules.swift` | The rules, and how the app runs shortcuts and shows notifications. |
| `Sources/Settings.swift` | The Settings window, and **Launch at Login**. |
| `Sources/MenuBar.swift` | Which values the menu bar shows. |
| `Sources/Updates.swift` | The daily check for a new release on GitHub. |
| `Tests/main.swift` | The tests of the app logic. |
| `Info.plist` | The bundle identifier, the version and the menu bar app settings. |
| `InternetAccessPolicy.plist` | The [Internet Access Policy](https://www.obdev.at/iap/), which tells firewalls such as Little Snitch which connections the app makes and why. Update it when the app connects to a new host. Its texts are in `Resources/*.lproj/InternetAccessPolicy.strings`. |
| `Resources/de.lproj/Localizable.strings` | The German texts of the app. |
| `build.sh` | Builds, installs and packages the app. |
| `test.sh` | Builds and runs the tests. |
| `scripts/make-icon.swift` | Draws `AppIcon.icns`. |
| `scripts/make-dmg-background.swift` | Draws `DMGBackground.tiff`, the background of the DMG window. |
| `scripts/make-dmg-layout.sh` | Saves `DMGLayout.DS_Store`, the Finder layout of the DMG window. |
| `.github/workflows/release.yml` | Builds the DMG and makes the GitHub release for a version tag. |
| `.github/workflows/tests.yml` | Runs the tests on a Mac. |
| `CHANGELOG.md` | The changes in each release. |

The project has no Xcode project and no Swift package. `build.sh` compiles the files in `Sources` with `swiftc`.

## Build and run

```sh
./build.sh --install
open ~/Applications/ClaudeUsageBar.app
```

Quit the running app before you open a new build. Use **Quit ClaudeUsageBar** in the app menu, or run:

```sh
osascript -e 'tell application id "de.marcgoertz.ClaudeUsageBar" to quit'
```

## Lint

CI fails on each SwiftLint violation. Run the same check before you commit:

```sh
swiftlint lint --strict
```

If you do not have SwiftLint, use Docker:

```sh
docker run --rm -v "$PWD":/work -w /work ghcr.io/realm/swiftlint:0.57.0 swiftlint lint --strict
```

## Test

The tests check the rules, the menu bar values, the texts of the limits, the version check and the list of shortcuts. CI runs them on each push and pull request. Run them before you commit:

```sh
./test.sh
```

`test.sh` compiles `Tests/main.swift` with the app code, without `Sources/main.swift`, and runs it in English with US formats. Add a test when you change the logic in `Usage.swift`, `Rules.swift`, `MenuBar.swift` or `Updates.swift`.

The tests do not cover the menu, the Settings window, notifications or running a shortcut. Build the app and check those changes in the app.

## Change the icon or the DMG window

1. Edit `scripts/make-icon.swift` or `scripts/make-dmg-background.swift`.
2. Run the script from the repository root, for example `swift scripts/make-dmg-background.swift`.
3. Commit the script and the file that it writes.

If you move the icons in the DMG background, also change their positions in `scripts/make-dmg-layout.sh`. Run it on a Mac with `scripts/make-dmg-layout.sh` and commit `DMGLayout.DS_Store`.

## Translations

The app is in English and German. The English texts are in the code, and they are also the keys for the German texts.

1. Put each new text in `String(localized:)`, for example `String(localized: "Refresh Now")`.
2. Add the German text to `Resources/de.lproj/Localizable.strings`. For a text with values, the key has `%lld` for a whole number and `%@` for other values, for example `"Every %lld Minutes" = "Alle %lld Minuten";`.
3. Build the app, then check the German texts. To start the app in German, run `build/ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar -AppleLanguages '(de)'`.

If you change a text in the code, also change its key in the German file. Otherwise the app shows the English text.

## Commits and pull requests

- Write commit messages in the [Conventional Commits](https://www.conventionalcommits.org/) format. For example: `fix: Show the error when the token is not valid.`
- Rebase your branch on `main`. Do not merge `main` into it.
- Add an entry under **Unreleased** in `CHANGELOG.md` for each change that users can see.
- Open a pull request on GitHub. CI runs SwiftLint on it.

## Release

The README has the release steps. In short: change the version in `Info.plist`, move the **Unreleased** entries in `CHANGELOG.md` to the new version, commit, and push a version tag such as `v0.4`. GitHub then builds the DMG and makes the release.
