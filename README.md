# Stash

Capture your ideas, tasks, and reminders instantly with a global hotkey on macOS. A minimal menu bar app with no unnecessary distractions.

## Features

- **Global Hotkey** - Accessible from anywhere with `Cmd+Shift+Space`
- **4 Categories** - Separate tasks (📥), questions (❓), goals (🎯), and reminders (🔔)
- **Local File Storage** - All notes are saved to a simple text file
- **Reminders Integration** - Reminder items (🔔) are synced with the native macOS Reminders app
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
- **Right click** - Context menu (open task file, preferences, quit)

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

Default: `~/Documents/my_tasks.txt`

### Change File Path Manually

```bash
defaults write com.robsonferreira.stash stash.taskFilePath "/path/to/your/file"
```

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
├── DumpMemory.swift     - Main app source (all app logic)
├── generate_icon.swift  - Icon generation script
├── build.sh             - Build script
├── icon.iconset/        - Icons output (from generate_icon.swift)
└── Stash.app/           - Compiled app bundle
```

### Debug Build

```bash
# Quick build (without icons)
swiftc DumpMemory.swift -framework Cocoa -o Stash

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

## Contributing

Ideas and improvements are welcome. Open an issue or submit a pull request.

### Future Ideas
- [ ] iCloud sync
- [ ] Search and filtering
- [ ] Customizable hotkey
- [ ] Custom light/dark themes
- [ ] Export as PDF

## License

MIT

## Author

Built by [your name / GitHub profile link]

---

**Stash** - Because your ideas deserve a safe, fast, and easy place to live.
