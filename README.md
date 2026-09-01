# ZCode Widget

A floating macOS dashboard panel for ZCode: token usage stats, searchable skill/plugin pickers, and a visual editor for custom model providers.

![macOS 13+](https://img.shields.io/badge/macOS-13.0%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Floating always-on-top panel** (~360×520pt) that lives in the macOS menu bar
- **Tokens tab** — token usage stats from `~/.zcode/cli/db/db.sqlite`, 7-day bar chart, recent turns list
- **Skills tab** — searchable picker of `~/.zcode/skills/` with copy-to-clipboard for slash commands
- **Plugins tab** — searchable picker with copy-to-clipboard
- **Providers tab** — visual editor for ZCode's custom model providers (`~/.zcode/v2/config.json`): add/edit/delete providers and models, custom headers, and a one-tap fix for gateways that return empty responses
- **Menu bar Z icon** — left-click toggles panel, right-click shows menu
- **Live updates** via FSEvents watcher on `~/.zcode/log/token-tail.jsonl`

## Installation

### Option A — Download the prebuilt app (no Xcode needed)

Grab the latest `ZCodeWidget.app.zip` from [Releases](../../releases), then:

```bash
unzip ZCodeWidget.app.zip -d /Applications
open /Applications/ZCodeWidget.app
```

> First launch: if macOS Gatekeeper blocks the app (unsigned build), right-click → **Open** → **Open**, or remove the quarantine flag:
> ```bash
> xattr -dr com.apple.quarantine /Applications/ZCodeWidget.app
> ```

### Option B — One-command install from source

```bash
git clone https://github.com/begumporshi-alt/zcode-widget.git
cd zcode-widget
./install.sh
```

The script checks prerequisites (Xcode command line tools, `xcodegen` — installs it via Homebrew if missing), builds a Release binary, installs to `/Applications`, and drops a `zcode-widget` launcher in `/usr/local/bin`.

### Option C — Manual build from source

Requirements: macOS 13.0+, Xcode (or its command line tools), `xcodegen`.

```bash
xcodegen generate
xcodebuild -project ZCodeWidget.xcodeproj -scheme ZCodeWidget \
    -configuration Release -derivedDataPath build build
open build/Build/Products/Release/ZCodeWidget.app
```

## Usage

| Action | How |
|---|---|
| Toggle panel | Click the **Z** icon in the menu bar (left-click), or run `zcode-widget` |
| Open menu | Right-click the **Z** icon → Show / Hide / Quit |
| Hide panel | Click **−** in the header |
| Close panel | Click **×** in the header (reopens via Z icon) |
| Copy slash command | Tap a skill/plugin in its tab |
| Edit model providers | **Providers** tab → tap a provider, or **+** to add one |
| Move panel | Drag anywhere on the panel |

### The Providers tab

Manages the same provider registry as ZCode's Settings (`~/.zcode/v2/config.json`) — everything you edit here is available in your ZCode chat model picker after a ZCode restart.

- **Provider editor** — name, protocol (anthropic / openai-compatible), base URL, API key, custom headers, enabled toggle
- **Model editor** — model ID, context/output limits, reasoning levels, input/output modalities
- **Apply empty-response fix** — one tap sets the protocol to `anthropic` and adds the Claude Code user-agent, for relay gateways (agentrouter etc.) that silently return empty streams to unrecognized clients

Safety: every save creates a timestamped backup (`config.json.bak-widget-*`, newest 10 kept), writes are atomic, and the widget warns if the ZCode IDE is running (quit ZCode before editing — it rewrites the config on exit).

## Project structure

```
zcode-widget/
├── install.sh                # One-command installer (Option B)
├── project.yml               # XcodeGen manifest (GRDB dependency)
├── Package.swift             # SwiftPM manifest
├── Resources/
│   └── Info.plist            # LSUIElement=true, bundle id com.zcode.widget
├── Sources/ZCodeWidget/
│   ├── ZCodeWidgetApp.swift  # App entry + AppDelegate (status bar, panel)
│   ├── Data/
│   │   ├── Database.swift    # GRDB DatabaseQueue (~/.zcode/cli/db/db.sqlite, readonly)
│   │   ├── Models.swift      # GRDB FetchableRecord structs
│   │   ├── TokenTailWatcher.swift    # FSEvents + polling watcher for live updates
│   │   ├── TokenUsageRepository.swift # Query helpers (totals, daily, recent turns)
│   │   └── ProviderConfigStore.swift # Read/write ~/.zcode/v2/config.json (surgical, backups)
│   ├── Discovery/
│   │   ├── SkillScanner.swift   # Scans ~/.zcode/skills/ for SKILL.md
│   │   └── PluginScanner.swift  # Reads installed_plugins.json + config.json
│   ├── UI/
│   │   ├── ContentView.swift    # Header + TabView (Tokens / Skills / Plugins / Providers)
│   │   ├── TokensView.swift     # Stats cards + chart + turn list
│   │   ├── SkillsView.swift     # Searchable skill picker + copy slash command
│   │   ├── PluginsView.swift    # Searchable plugin picker + copy slash command
│   │   ├── ProvidersView.swift  # Provider list + editors (provider, model)
│   │   └── ToastView.swift      # Copy-to-clipboard feedback toast
│   └── Window/
│       └── FloatingPanelController.swift  # KeyablePanel (typing-capable borderless panel)
└── zcode-widget              # Shell launcher script (dev copy)
```

## Database

The widget reads from `~/.zcode/cli/db/db.sqlite` using GRDB in read-only mode. Key tables:

- **`model_usage`** — per-API-call records (id, session_id, turn_id, model_id, provider_id, tokens, started_at)
- **`turn_usage`** — per-turn aggregates (session_id, turn_id, started_at, tokens, status)
- **`session`** — session metadata

Note: `started_at` is stored as **INTEGER milliseconds** since Unix epoch (not ISO strings).

## Notes

- The app is a background accessory (`LSUIElement = true`), so it won't appear in the Dock — look for the **Z** icon in the menu bar.
- All data paths are read from the current user's home directory; the widget never writes anywhere except provider-config edits (with backup) in `~/.zcode/v2/`.

## License

MIT — do whatever you like; attribution appreciated.
