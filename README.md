# Stash

Stash your ideas, tasks, and reminders instantly with a global hotkey on macOS. A minimal menu bar app with no unnecessary distractions.

![macOS](https://img.shields.io/badge/macOS-10.14%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-pure-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-green)
![No Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

## Features

- **Global Hotkey** - Accessible from anywhere with `Cmd+Shift+Space`
- **4 Categories** - Separate tasks (📥), questions (❓), goals (🎯), and reminders (🔔)
- **Local File Storage** - All notes are saved to a simple text file
- **Reminders Integration** - Reminder items (🔔) are synced with the native macOS Reminders app
- **Built-in Localization** - `en-US` (default) and `pt-BR` using Apple `.lproj` best practices
- **Language Switcher** - Choose `System`, `English (US)`, or `Português (Brasil)` in **Preferences...**
- **Improved Popover UX** - Top icons centered and keyboard hint line (`Enter` / `Esc`) better distributed and readable
- **Built-in Help** - Help button in the popover with global hotkey and task-type shortcuts
- **About Panel** - Quick access to app details via menu and Help window
- **Versioned Release** - Current version: `0.2.0`
- **No Dependencies** - Built 100% in Swift using only native macOS frameworks
- **Menu Bar App** - Stays in the menu bar and out of the Dock
- **Lightweight** - Single-screen app, fast and responsive

## Quick Start

### Requirements
- macOS 10.14+
- Xcode Command Line Tools (or Swift 5+)

### Build and Install

```bash
# Clone the repository
git clone https://github.com/your-username/stash.git
cd stash

# Build the app
./build.sh

# Install to /Applications
cp -r Stash.app /Applications/

# Or run directly
open Stash.app
```

**Note:** On first launch, macOS may block an unsigned app. Solution: right-click `Stash.app` -> **Open** -> **Open Anyway**.

## Usage

### Using the Hotkey
- Press **`Cmd+Shift+Space`** from any app
- Type your note
- Press **`Enter`** to save or **`Esc`** to cancel

### Using the Menu Bar
- **Left click** - Opens the panel
- **Right click** - Context menu (open task file, preferences, help, about, quit)

### Help and About
- Click the **Help** button (`?`) in the popover to open quick help.
- The Help window shows:
- Global hotkey (`Cmd+Shift+Space`)
- Type shortcuts (`Cmd+1` to `Cmd+4`)
- Save/cancel shortcuts (`Enter` / `Esc`)
- App version
- Open **About** from the menu bar context menu or from the Help window.

### Categories

```
📥 Task           - Action item
❓ Question       - Something to investigate
🎯 Goal           - A target to achieve
🔔 Reminder       - Synced to macOS Reminders
```

Use `Cmd+1`, `Cmd+2`, `Cmd+3`, or `Cmd+4` to switch categories quickly.

## Configuration

Open context menu -> **Preferences...**

- **Task file** - Sets the file path where notes are saved (auto-created if missing)
- **App language** - `System`, `English (US)`, or `Português (Brasil)`
- **Gemini model** - Model used to parse natural language reminder text
- **AI provider** - Choose between `Google`, `OpenAI`, or `Anthropic`
- **AI model** - Model used to parse natural language reminder text
- **API key** - Stored in macOS Keychain for the selected provider (never hardcoded in source)

Default: `~/Documents/my_tasks.txt`

### Change File Path Manually

```bash
defaults write com.robsonferreira.stash stash.taskFilePath "/path/to/your/file"
```

### AI Reminder Parsing (Google / OpenAI / Anthropic)

For reminder entries (🔔), Stash can parse natural language such as:

`Lembrar as 16:30 de tomar remedio`

and extract:
- Reminder title
- Date and time (when confidently inferred)

How to configure:
1. Open **Preferences...** from the menu bar context menu.
2. Choose **AI provider** (`Google`, `OpenAI`, or `Anthropic`).
3. Fill **API key** for that provider (saved in Keychain).
4. Keep or edit **AI model** (default for Google: `gemini-3-flash-preview`).

Alternative (environment variable):

```bash
export GOOGLE_API_KEY="your-google-api-key"
export OPENAI_API_KEY="your-openai-api-key"
export ANTHROPIC_API_KEY="your-anthropic-api-key"
```

Key security notes:
- API keys are not hardcoded in the project.
- API keys are not stored in git-tracked files.

## Localization

- Default language: `en-US`
- Additional language: `pt-BR`
- Implementation uses Apple localization folders (`*.lproj`) and `Localizable.strings`/`InfoPlist.strings`
- The selected app language is persisted in `UserDefaults` (`stash.language`)
- Reminder AI parsing receives the active app language (`en-US` or `pt-BR`) as context

## File Format

The file is grouped by date:

```
📅 20/02/2026
    🔔 Review PR for project X
    📥 Buy coffee
    ❓ How does GraphQL work?

📅 19/02/2026
    🎯 Complete documentation
    📥 Send email to client
```

Notes are simple text lines, so they are easy to edit manually when needed.

## Development

### Project Structure

```
.
├── Stash.swift          - Main app source (all app logic)
├── generate_icon.swift  - Icon generation script
├── build.sh             - Build script
├── en-US.lproj/         - English localization resources
├── pt-BR.lproj/         - Portuguese (Brazil) localization resources
├── icon.iconset/        - Icons output (from generate_icon.swift)
└── Stash.app/           - Compiled app bundle
```

### Debug Build

```bash
# Quick build (without icons)
swiftc Stash.swift -framework Cocoa -o Stash

# Full build
./build.sh
```

### Accessibility

The app needs Accessibility permission to capture the global hotkey. On first run, macOS will prompt for access - **click "OK"**.

You can also enable it manually:
1. **System Settings** -> **Privacy & Security** -> **Accessibility**
2. Find `Stash` in the list and enable it

## Distribution

To share a signed app:

```bash
# Create a .dmg file
hdiutil create -volname "Stash" -srcfolder Stash.app -ov -format UDZO Stash.dmg
```

## Changelog

- See [CHANGELOG.md](CHANGELOG.md) for release notes.
- Current release: `0.2.0`

## Contributing

Ideas and improvements are welcome. Open an issue or submit a pull request.

### Future Ideas
- [ ] iCloud sync
- [ ] Search and filtering
- [ ] Customizable hotkey
- [ ] Custom light/dark themes
- [ ] Export as PDF

## Support

If you find Stash useful, consider buying me a coffee:

<a href="https://buymeacoffee.com/robsonferr" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width="180"></a>

## License

MIT

## Author

Built by [your name / GitHub profile link]

---

**Stash** - Because your ideas deserve a safe, fast, and easy place to live.
