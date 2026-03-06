# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog,
and this project adheres to Semantic Versioning.

## [0.4.1] - 2026-03-06

### Added
- About panel now includes direct links for:
  - **GitHub Repository**: `https://github.com/robsonferr/stash`
  - **Report an issue**: `https://github.com/robsonferr/stash/issues/new`

### Changed
- Version bumped to `0.4.1` across `build.sh`, `Stash.swift`, and `README.md`.

## [0.4.0] - 2026-03-03

### Added
- **Rewind the Day** — new daily review notification feature.
  - Set a daily reminder time in Preferences ("Rewind the Day" section) with a time picker (weekdays only, Mon–Fri).
  - macOS notification arrives at the configured time (default: 17:30) with three action buttons: **Review my day**, **Remind me in 1 hour**, and **Not today**.
  - Snooze ("Remind me in 1 hour") can be used up to 2 times per day; on the third notification the snooze option is no longer offered.
  - Selecting **Review my day** from the notification opens the day review screen with an exclusive **"Mark day as reviewed 🌅"** button (only visible when opened via notification).
  - Clicking "Mark day as reviewed 🌅" appends the 🌅 emoji to the day's date header in the task file (`📅 dd/MM/yyyy 🌅`) and cancels any pending snooze notification.
  - Notification is suppressed automatically if the day has already been marked as reviewed before the scheduled time.
  - Notification permission is requested only when the feature is first enabled in Preferences.
- **Version bumped to `0.4.0`** across `build.sh`, `Stash.swift`, and `README.md`.

## [0.3.0] - 2026-02-26

### Added
- **Landing Page** — new `web/` folder with a fully self-contained static landing page (`index.html`) for the Stash project.
  - Hero section with global hotkey visual, download/GitHub CTAs, and project metadata.
  - Features grid, "How It Works" steps, categories showcase, file format preview, and AI parsing demo.
  - Responsive dark theme, inline CSS, no build step required.
  - Uses the actual app icon in navigation and footer.
- **Reminder Notification** — added notification support for reminders.

### Changed
- Version bumped to `0.3.0` across `build.sh`, `Stash.swift`, `README.md`, and landing page.

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
