# ZCode Widget

A floating macOS dashboard panel for ZCode that shows token usage stats from the ZCode SQLite database, a searchable skill/plugin picker, and one-tap copy-to-clipboard for slash commands.

## Features

- **Floating always-on-top panel** (~360×520pt) that lives in the macOS menu bar
- **Tokens tab** — token usage stats from `~/.zcode/cli/db/db.sqlite`, 7-day bar chart, recent turns sparkline
- **Skills tab** — searchable picker of `~/.zcode/skills/` with copy-to-clipboard for slash commands
- **Plugins tab** — searchable picker with copy-to-clipboard
- **Menu bar Z icon** — left-click toggles panel, right-click shows menu
- **Live updates** via FSEvents watcher on `~/.zcode/log/token-tail.jsonl`

## Requirements

- macOS 13.0+
- Swift 5.9+
- Xcode (or `xcodegen` for project generation)
- ZCode CLI installed (for the database path)

## Quick start

```bash
# 1. Generate Xcode project
xcodegen generate

# 2. Build
xcodebuild -project ZCodeWidget.xcodeproj -scheme ZCodeWidget -configuration Debug build

# 3. Launch
open build/Build/Products/Debug/ZCodeWidget.app
```

Or use the helper script:
```bash
zcode-widget   # launches or toggles the widget
```

## Usage

| Action | How |
|---|---|
| Toggle panel | Click the **Z** icon in the menu bar (left-click) |
| Open menu | Right-click the **Z** icon → Show / Hide / Quit |
| Hide panel | Click **−** in the header |
| Close panel | Click **×** in the header (reopens via Z icon) |
| Copy slash command | Tap a skill/plugin in its tab |
| Move panel | Drag anywhere on the title bar |

## Project structure

```
zcode-widget/
├── project.yml               # XcodeGen manifest (GRDB dependency)
├── Package.swift             # SwiftPM manifest
├── Resources/
│   └── Info.plist            # LSUIElement=true, bundle id com.zcode.widget
├── Sources/ZCodeWidget/
│   ├── ZCodeWidgetApp.swift  # App entry + AppDelegate (status bar, panel)
│   ├── Data/
│   │   ├── Database.swift    # GRDB DatabaseQueue (~/.zcode/cli/db/db.sqlite, readonly)
│   │   ├── Models.swift      # GRDB FetchableRecord structs
│   │   ├── TokenTailWatcher.swift # FSEvents + polling watcher for live updates
│   │   └── TokenUsageRepository.swift # Query helpers (totals, daily, recent turns)
│   ├── Discovery/
│   │   ├── SkillScanner.swift   # Scans ~/.zcode/skills/ for SKILL.md
│   │   └── PluginScanner.swift  # Reads installed_plugins.json + config.json
│   ├── UI/
│   │   ├── ContentView.swift    # Header + TabView (Tokens / Skills / Plugins)
│   │   ├── TokensView.swift     # Stats cards + chart + turn list
│   │   ├── SkillsView.swift     # Searchable skill picker + copy slash command
│   │   ├── PluginsView.swift    # Searchable plugin picker + copy slash command
│   │   └── ToastView.swift      # Copy-to-clipboard feedback toast
│   └── Window/
│       └── FloatingPanelController.swift  # NSPanel, level=.floating, movable
└── zcode-widget             # Shell launcher script
```

## Database

The widget reads from `~/.zcode/cli/db/db.sqlite` using GRDB in read-only mode. Key tables:

- **`model_usage`** — per-API-call records (id, session_id, turn_id, model_id, provider_id, tokens, started_at)
- **`turn_usage`** — per-turn aggregates (session_id, turn_id, started_at, tokens, status)
- **`session`** — session metadata

Note: `started_at` is stored as **INTEGER milliseconds** since Unix epoch (not ISO strings).

## Building

### From Xcode

```bash
xcodegen generate
open ZCodeWidget.xcodeproj
# ⌘B to build, ⌘R to run
```

### From command line

```bash
xcodebuild -project ZCodeWidget.xcodeproj -scheme ZCodeWidget -configuration Debug build
open build/Build/Products/Debug/ZCodeWidget.app
```

## Testing

The app is a background accessory (`LSUIElement = true`), so it won't appear in the Dock. Look for the **Z** icon in the menu bar.

## License

This project is private. See repository settings for access.