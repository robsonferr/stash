# Copilot Instructions for `stash`

## Build, test, and lint commands

- Full app bundle build (recommended):
  - `./build.sh`
- Quick debug compile (no `.app` bundle/icons/signing):
  - `swiftc Stash.swift -framework Cocoa -o Stash`
- Run the built app bundle:
  - `open Stash.app`

Testing/linting status in this repo:
- No automated test suite is configured (`swift test`/Xcode test target not present).
- No linter configuration is present (no SwiftLint/SwiftFormat config in repo).
- Single-test command: not available in current repository setup.

## High-level architecture

- The app is intentionally single-file for runtime logic: `Stash.swift` contains app entrypoint, menu bar wiring, popover UI, preferences window, help window, AI reminder parsing, and file/reminder persistence.
- Build packaging is script-driven (`build.sh`), not Xcode-project driven:
  - compiles `Stash.swift` with Cocoa/EventKit/Security
  - generates icons via `generate_icon.swift` + `iconutil`
  - copies `.lproj` localization folders into `Stash.app`
  - emits `Info.plist` and signs ad-hoc by default (or with `CODE_SIGN_IDENTITY`)
- Core runtime flow:
  - `AppDelegate` owns menu bar item, popover lifecycle, context menu, and global hotkey (`Cmd+Shift+Space`)
  - `TaskViewController` handles fast capture UI and save flow
  - non-reminder items are appended to local task file
  - reminder items (`🔔`) are AI-parsed first, then created in Apple Reminders (`EventKit`)
- AI reminder parsing supports `Google`, `OpenAI`, and `Anthropic`, with provider/model in `UserDefaults` and keys resolved from Keychain first, then environment variables.
- Localization is runtime-switchable (`en-US`, `pt-BR`, `system`) using `.lproj` resources and a custom `Localizer`.

## Key codebase conventions

- Keep user-facing app logic in `Stash.swift` sections (`// MARK:` blocks) unless there is a strong reason to split files.
- For localized UI text, always use `L("key")` / `LF("key", ...)` and add matching keys to both:
  - `en-US.lproj/Localizable.strings`
  - `pt-BR.lproj/Localizable.strings`
- Task type behavior is centralized in `kIcons` (symbol + tooltip/placeholder/description localization keys). If adding/changing task types, update `kIcons` and shortcut/tooltips together.
- Persisted task file format is append-by-day and emoji-prefixed; preserve this exact shape when changing write logic:
  - day header: `📅 dd/MM/yyyy`
  - entry line: four-space indent + `<emoji> <text>`
- Reminder save path convention:
  - write to local task file first
  - then create `EKReminder` in list named `Stash`
  - show localized success/error status in popover
- Preferences persistence conventions:
  - `UserDefaults` keys are `stash.*` namespaced
  - API keys are stored in Keychain service `com.robsonferreira.stash` (never in repo files)
  - env var fallback names are `GOOGLE_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`
