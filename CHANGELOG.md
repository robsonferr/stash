# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog,
and this project adheres to Semantic Versioning.

## [0.1.0] - 2026-02-20

### Added
- Initial menu bar app flow for fast task capture via global hotkey (`Cmd+Shift+Space`).
- Four task types with shortcuts (`Cmd+1` to `Cmd+4`): task, question, goal, reminder.
- Reminder integration with Apple Reminders (`EventKit`).
- AI reminder parsing with provider selection (`Google`, `OpenAI`, `Anthropic`).
- API key storage in Keychain and optional environment variable fallback.
- Preferences window with task file path, language selection, AI provider/model, and key management.
- Localization using Apple `.lproj` resources for `en-US` (default) and `pt-BR`.
- Help window with shortcuts overview and integrated About action.
- About entry in context menu and app version display in Help/Preferences.
- Contextual description text under the input field for each task type.

### Changed
- Main source file renamed from `DumpMemory.swift` to `Stash.swift`.
- Popover UX improvements: centered type icons and clearer `Enter`/`Esc` hint layout.
- Build metadata updated to `CFBundleShortVersionString = 0.1.0`.

### Documentation
- README updated with localization, Help/About, support section, and release notes references.
