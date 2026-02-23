# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog,
and this project adheres to Semantic Versioning.

## [0.2.0] - 2026-02-23

### Added
- **Review Window** — new "Review" submenu in the menu bar context menu with two options:
  - **Review my day** — shows all entries captured today.
  - **Review my week** — shows the last 7 days, grouped by date with a `📅` day header.
- **Mark as done** — each entry in the Review Window has a toggle button (`○` / `✅`). Clicking it marks or unmarks the item as complete.
- **Completion format** — when an item is marked done, the source task file is updated in-place with a `✅ DD/MM/YYYY` suffix on the same line, making it both human-readable and machine-parseable.
- **Empty state** — periods with no entries display a localized "No notes for this period." message.
- **StashFileParser** — internal parser that reads the task file into structured `DayBlock`/`StashEntry` models, used as the foundation for future features (AI insights, search, etc.).
- Localization: all new strings available in `en-US` and `pt-BR`.

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
