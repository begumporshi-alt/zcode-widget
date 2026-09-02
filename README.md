# ZCode Widget

A floating macOS dashboard panel for ZCode: token usage stats, searchable skill/plugin pickers, and a visual editor for custom model providers.

![macOS 13+](https://img.shields.io/badge/macOS-13.0%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Floating always-on-top panel** (440×560pt) that lives in the macOS menu bar, with a scrollable sidebar (7 sections) — ⌘1…⌘7 jump straight to a section
- **Tokens tab** — token usage stats from `~/.zcode/cli/db/db.sqlite`, 7-day bar chart, usage streak, recent turns list
- **Skills tab** — searchable picker of `~/.zcode/skills/` with copy-to-clipboard for slash commands
- **Plugins tab** — searchable picker with copy-to-clipboard
- **Providers tab** — visual editor for ZCode's custom model providers (`~/.zcode/v2/config.json`): add/edit/delete providers and models, custom headers, and a one-tap fix for gateways that return empty responses
- **Report tab** — one-tap weekly shareable summary card (copy as 2× PNG) plus a 119-day activity heatmap
- **Prompts tab** — LLM-powered prompt enhancer (uses your configured ZCode providers) and a prompt library with curated built-ins plus your own saved prompts
- **Database tab** — per-project database dashboard: auto-discovers the projects you work on in ZCode, then inventories each project's migrations, tables & columns (with RLS badges), row-level security policies, functions, triggers, connection hints (key names only — values are never read), and architecture/blueprint notes from ZCode memories + in-repo docs
- **Menu bar glance** — the Z icon shows today's token usage, turning red when you pass your daily budget (set in Settings); left-click toggles the panel, right-click shows a menu
- **Activity ticker** — live strip at the bottom showing the latest model calls as they land
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

The script checks prerequisites (Xcode command line tools, `xcodegen` — installs it via Homebrew if missing), builds a Release binary, installs to `/Applications`, drops a `zcode-widget` launcher in `/usr/local/bin`, and installs the `database-expert` ZCode subagent to `~/.zcode/agents/`.

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
| Jump to a section | Click a sidebar item, or press **⌘1…⌘7** (Tokens…Database) |
| Open menu | Right-click the **Z** icon → Show / Hide / Quit |
| Hide panel | Click **−** in the footer |
| Copy slash command | Tap a skill/plugin in its tab |
| Edit model providers | **Providers** tab → tap a provider, or **+** to add one |
| Set daily budget | Gear icon in the footer → Settings |
| Track a project's database | **Database** tab → **+** to add any folder |
| Move panel | Drag anywhere on the panel (position is remembered) |

### The Providers tab

Manages the same provider registry as ZCode's Settings (`~/.zcode/v2/config.json`) — everything you edit here is available in your ZCode chat model picker after a ZCode restart.

- **Provider editor** — name, protocol (anthropic / openai-compatible), base URL, API key, custom headers, enabled toggle
- **Model editor** — model ID, context/output limits, reasoning levels, input/output modalities
- **Apply empty-response fix** — one tap sets the protocol to `anthropic` and adds the Claude Code user-agent, for relay gateways (agentrouter etc.) that silently return empty streams to unrecognized clients

Safety: every save creates a timestamped backup (`config.json.bak-widget-*`, newest 10 kept), writes are atomic, and the widget warns if the ZCode IDE is running (quit ZCode before editing — it rewrites the config on exit).

### The Database tab

Shows every project you've worked on in ZCode (from `session` history, most recent first — plus any folders you add with **+**). Each project gets a read-only inventory parsed from its migration/schema SQL (`supabase/migrations/**`, `migrations/**`, `sql/**`, `schema.sql`):

- **Tables & Schema** — every table with its columns and types; tables with row-level security show an **RLS** badge; expand any table to browse its schema
- **RLS Policies** — each policy with its table, command and roles
- **Functions & Triggers** — parsed names with signatures (`returns …` / `BEFORE … ON …`)
- **Connections** — which connection keys a project's `.env`/`config.toml`/`docker-compose` declares (e.g. Supabase URL, service-role key, direct DB URL). **Only key names are matched — values are never read, displayed, or stored.**
- **Blueprints & Docs** — architecture/blueprint notes ZCode kept for the project (memory files) plus `ARCHITECTURE.md`/`docs/**` inside the repo, with one-line summaries

SQL parsing is comment- and string-aware, deduplicates re-imported migration files and objects, and caps the work per project so it stays instant even on large repos.

### The database-expert subagent

The repo also ships a ZCode subagent definition (`agents/database-expert.md`, installed to `~/.zcode/agents/` by `install.sh`) — the intelligent counterpart to the Database tab. In any new ZCode session it's available as the `database-expert` agent: ask ZCode anything about your projects' databases — RLS coverage, index gaps, trigger behavior, query performance, migration reviews, health sweeps — and ZCode can delegate to it.

- **Project-aware** — discovers your projects from ZCode's session history and rebuilds current schema knowledge (tables, RLS policies, functions, triggers, **indexes**, and integrity constraints) from migration files on every invocation
- **Read-only by default** — observes, analyzes, advises, answers; never modifies the database or project files unless explicitly instructed; connects to a live database only when you explicitly ask
- **Always answers in a fixed structure** — 1) issue/question, 2) assessment with evidence (file:line, counts), 3) recommended actions with expected impact, effort, and priority — plus alerts it found on its own
- **Secrets-safe** — `.env` key names only; connection values are never displayed (used transiently, never echoed, only for explicitly-requested live checks)

## Project structure

```
zcode-widget/
├── install.sh                # One-command installer (Option B)
├── project.yml               # XcodeGen manifest (GRDB dependency)
├── Package.swift             # SwiftPM manifest
├── agents/
│   └── database-expert.md    # ZCode subagent: database expert behind the Database tab
├── Resources/
│   └── Info.plist            # LSUIElement=true, bundle id com.zcode.widget
├── Sources/ZCodeWidget/
│   ├── ZCodeWidgetApp.swift  # App entry + AppDelegate (status bar glance, menus, panel)
│   ├── Data/
│   │   ├── AppState.swift          # Shared selected-section state
│   │   ├── Database.swift          # GRDB DatabaseQueue (~/.zcode/cli/db/db.sqlite, readonly)
│   │   ├── Models.swift            # GRDB FetchableRecord structs
│   │   ├── TokenTailWatcher.swift  # FSEvents + polling watcher for live updates
│   │   ├── TokenUsageRepository.swift  # Query helpers (totals, daily, recent turns)
│   │   ├── ProviderConfigStore.swift  # Read/write ~/.zcode/v2/config.json (surgical, backups)
│   │   ├── PromptEnhancer.swift    # LLM enhance calls through configured providers
│   │   ├── PromptLibraryStore.swift # Prompt library (~/.zcode/prompts.json)
│   │   ├── WidgetSettingsStore.swift # Daily budget + pinned folders (~/.zcode/widget-settings.json)
│   │   └── ActivityTicker.swift    # Latest-call ticker state
│   ├── Database/
│   │   ├── ProjectDbScanner.swift  # Discovers projects + parses SQL → tables/policies/functions/triggers
│   │   └── ProjectDbModels.swift   # Inventory structs
│   ├── Discovery/
│   │   ├── SkillScanner.swift   # Scans ~/.zcode/skills/ for SKILL.md
│   │   └── PluginScanner.swift  # Reads installed_plugins.json + config.json
│   ├── UI/
│   │   ├── ContentView.swift    # Sidebar + section switcher (7 sections)
│   │   ├── TokensView.swift     # Stats cards + chart + streak + turn list
│   │   ├── SkillsView.swift     # Searchable skill picker + copy slash command
│   │   ├── PluginsView.swift    # Searchable plugin picker + copy slash command
│   │   ├── ProvidersView.swift  # Provider list + editors (provider, model)
│   │   ├── ReportView.swift     # Weekly shareable card + heatmap
│   │   ├── PromptsView.swift    # Prompt enhancer + library
│   │   ├── DatabaseView.swift   # Per-project database dashboard
│   │   ├── SettingsView.swift   # Settings sheet (daily budget)
│   │   ├── ActivityTickerBar.swift  # Live bottom ticker strip
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
