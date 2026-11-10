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
| `Sources/main.swift` | All of the app code. |
| `Info.plist` | The bundle identifier, the version and the menu bar app settings. |
| `build.sh` | Builds, installs and packages the app. |
| `scripts/make-icon.swift` | Draws `AppIcon.icns`. |
| `scripts/make-dmg-background.swift` | Draws `DMGBackground.tiff`, the background of the DMG window. |
| `scripts/make-dmg-layout.sh` | Saves `DMGLayout.DS_Store`, the Finder layout of the DMG window. |
| `.github/workflows/release.yml` | Builds the DMG and makes the GitHub release for a version tag. |
| `CHANGELOG.md` | The changes in each release. |

The project has no Xcode project and no Swift package. `build.sh` compiles `Sources/main.swift` with `swiftc`.

## Build and run

```sh
./build.sh --install
open ~/Applications/ClaudeUsageBar.app
```

Quit the running app before you open a new build. Use **Quit** in the app menu, or run:

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

The project has no automatic tests. Build the app and do a check of the change in the menu bar.

## Change the icon or the DMG window

1. Edit `scripts/make-icon.swift` or `scripts/make-dmg-background.swift`.
2. Run the script from the repository root, for example `swift scripts/make-dmg-background.swift`.
3. Commit the script and the file that it writes.

If you move the icons in the DMG background, also change their positions in `scripts/make-dmg-layout.sh`. Run it on a Mac with `scripts/make-dmg-layout.sh` and commit `DMGLayout.DS_Store`.

## Commits and pull requests

- Write commit messages in the [Conventional Commits](https://www.conventionalcommits.org/) format. For example: `fix: Show the error when the token is not valid.`
- Rebase your branch on `main`. Do not merge `main` into it.
- Add an entry under **Unreleased** in `CHANGELOG.md` for each change that users can see.
- Open a pull request on GitHub. CI runs SwiftLint on it.

## Release

The README has the release steps. In short: change the version in `Info.plist`, move the **Unreleased** entries in `CHANGELOG.md` to the new version, commit, and push a version tag such as `v0.2`. GitHub then builds the DMG and makes the release.
