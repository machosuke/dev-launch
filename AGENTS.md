# Repository Guidelines

## Project Structure & Module Organization

DevLaunch is a macOS 13+ SwiftUI menu bar app. Main code lives in `DevLaunch/`:

- `DevLaunch/Models/` contains domain types such as projects, editor presets, and app settings.
- `DevLaunch/Services/` contains scanning, launch, login item, terminal, and shortcut integrations.
- `DevLaunch/ViewModels/` contains state and presentation logic.
- `DevLaunch/Views/` contains SwiftUI views, with settings screens under `DevLaunch/Views/Settings/`.
- `DevLaunch/Assets.xcassets/`, `Info.plist`, and `DevLaunch.entitlements` contain resources and macOS permissions.

Tests live in `Tests/`. XcodeGen source of truth is `project.yml`; regenerate `DevLaunch.xcodeproj` after changing targets, settings, sources, or entitlements. Planning and experiments live in `plans/`, `Assets/plans/`, and `poc/`.

## Build, Test, and Development Commands

- `xcodegen generate`: regenerate `DevLaunch.xcodeproj` from `project.yml`.
- `open DevLaunch.xcodeproj`: open the app in Xcode.
- `xcodebuild -scheme DevLaunch -destination 'platform=macOS' build`: build the macOS app from the command line.
- `xcodebuild -scheme DevLaunch -destination 'platform=macOS' test`: run the unit test target.
- `./poc/stability_test.sh`: run the PoC stability check when working on launch or terminal behavior.

## Coding Style & Naming Conventions

Use Swift 5.9 and existing SwiftUI conventions. Prefer 4-space indentation, `PascalCase` for types, `camelCase` for properties/functions, and service names ending in `Manager`, `Launcher`, or `Scanner` when matching existing patterns. Keep views small; place app integration code in `Services/` rather than SwiftUI views. Avoid new dependencies unless justified in `project.yml`.

## Testing Guidelines

Tests use XCTest in `Tests/` with `@testable import DevLaunch`. Name tests with the `testExpectedBehavior` pattern, for example `testDetectsGitRepositories`. Use temporary directories and isolated fixtures for filesystem behavior, as in `ProjectScannerTests`. Add tests for scanner, launcher, settings persistence, and permission-sensitive changes.

## Commit & Pull Request Guidelines

Recent history uses concise subjects such as `feat: Phase 2 - implement core features (scan + launch)` and `Add Phase 0 PoC: integrated terminal launch verification`. Prefer imperative, scoped messages; use `feat:` for feature phases when appropriate.

Pull requests should include a short summary, test/build results, linked issue or plan reference, and screenshots or recordings for UI changes. Note macOS permission, entitlement, Apple Events, Accessibility, or sandbox changes explicitly.

## Security & Configuration Tips

The app disables sandboxing and uses Apple Events/Accessibility for editor and terminal automation. Keep permission prompts and usage descriptions accurate, do not hardcode local paths or secrets, and validate external command launch behavior carefully.
