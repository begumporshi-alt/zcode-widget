# ZCode Widget

A floating macOS dashboard panel for ZCode: token usage stats, searchable skill/plugin pickers, and a visual editor for custom model providers.

![macOS 13+](https://img.shields.io/badge/macOS-13.0%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Floating always-on-top panel** that lives in the macOS menu bar, with a scrollable sidebar (11 sections) — ⌘1…⌘9 / ⌘0 jump straight to a section (the Design Library tab is click-only). Drag the grip in the bottom-right corner to resize (440×560pt default, minimum 360×480); position and size are remembered between launches
- **Tokens tab** — token usage stats from `~/.zcode/cli/db/db.sqlite`, 7-day bar chart, usage streak, recent turns list
- **Skills tab** — searchable picker of `~/.zcode/skills/` with copy-to-clipboard for slash commands
- **Plugins tab** — searchable picker with copy-to-clipboard
- **Providers tab** — visual editor for ZCode's custom model providers (`~/.zcode/v2/config.json`): add/edit/delete providers and models, custom headers, and a one-tap fix for gateways that return empty responses
- **Report tab** — one-tap weekly shareable summary card (copy as 2× PNG) plus a 119-day activity heatmap
- **Prompts tab** — LLM-powered prompt enhancer (uses your configured ZCode providers) and a prompt library with curated built-ins plus your own saved prompts
- **Design Library tab** — a searchable library of design directions (seeded with 7 clothing-ecommerce concepts): palettes with click-to-copy hex swatches, typography pairings, imagery/layout guidance, page-by-page application notes, reference sites, and a one-tap **Copy brief as Markdown** export; add your own directions alongside the built-ins
- **Database tab** — per-project database dashboard: auto-discovers the projects you work on in ZCode, then inventories each project's migrations, tables & columns (with RLS badges), row-level security policies, functions, triggers, connection hints (key names only — values are never read), and architecture/blueprint notes from ZCode memories + in-repo docs
- **Tasks tab** — personal task manager with reminders: tasks with due dates & times, priorities and notes; macOS notification at the due time (with a **Mark Done** action), due-soon badge on the sidebar and menu-bar tooltip, and quick access to due tasks from the Z icon's right-click menu
- **Thermal tab** — macOS heat monitor & management: watches the OS's own thermal pressure (raw °C sensors need admin rights on Apple Silicon, so the widget reads `ProcessInfo.thermalState` + live per-process CPU instead), shows the heaviest processes, and records heat alerts that name the hot process **and the ZCode chat that was active** when the machine heated up. When it gets hot: a notification banner (tap → opens the Thermal tab), a red flame badge on the sidebar, an in-widget alerts history (`~/.zcode/widget-thermal.json`), and cool-down helpers (Activity Monitor, open the hot chat's project folder). Detection runs even while the panel is hidden
- **Captures tab** — screenshots & screen recordings with an in-widget gallery: **Screen** captures the display the ZCode chat is on, **Window** captures just the chat window, **Record** records the display until you press Stop (the widget hides itself so it never appears in its own captures; the menu-bar icon shows a red dot while recording and its right-click menu can stop it). Every capture lands in `~/.zcode/captures/` with a thumbnail grid, image/video previews, duration chips, Copy / Reveal / Delete, and **Send to chat** — writes the screenshot into a chosen ZCode chat's own input queue (the same one the ZCode UI uses), falling back to copy-to-clipboard if ZCode doesn't pick it up within ~20 s. Two optional privacy/audio features: **blur sensitive areas** (draw boxes once; every screenshot and recording gets them redacted — blur or pixelate, unblurred originals are never kept) and **voice-over narration** (records your microphone alongside the screen). Needs macOS Screen Recording permission once (Settings → Privacy & Security → Screen & System Audio Recording → ZCodeWidget; macOS may ask for Touch ID/password, and the widget should be quit & reopened after granting — note each rebuilt binary needs the grant again)
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
| Jump to a section | Click a sidebar item, or press **⌘1…⌘9 / ⌘0** (Tokens…Thermal, Captures — Design Library is click-only) |
| Open menu | Right-click the **Z** icon → Show / Hide / Quit |
| Hide panel | Click **−** in the footer |
| Copy slash command | Tap a skill/plugin in its tab |
| Edit model providers | **Providers** tab → tap a provider, or **+** to add one |
| Set daily budget | Gear icon in the footer → Settings |
| Track a project's database | **Database** tab → **+** to add any folder |
| Add a task | **Tasks** tab → **New** → type a title, optionally set a due date/time (reminders go on at the due time) |
| See due tasks | **Z** icon right-click menu lists tasks due within 24 h; click one to open the Tasks tab |
| See if the Mac is hot | **Thermal** tab shows live status + heaviest processes; when macOS reports serious/critical pressure a banner names the hot process and the chat that was active, and the sidebar shows a red flame |
| Take a screenshot | **Captures** tab → **Screen** (whole display the ZCode chat is on) or **Window** (chat window only) |
| Record the screen | **Captures** tab → **Record**, then **Stop** (or the Z icon's right-click menu); files land in `~/.zcode/captures/` |
| Send a capture to a chat | **Captures** tab → select a screenshot → **Send to chat** (pick the target chat next to the button) |
| Blur sensitive info | **Captures** tab → enable **Blur sensitive areas** → **Edit areas…** → drag boxes over anything sensitive (choose Blur or Pixelate) |
| Record with narration | **Captures** tab → enable **Voice-over narration (microphone)** → **Record** (asks for mic permission the first time) |
| Move panel | Drag anywhere on the panel (position is remembered) |
| Resize panel | Drag the **corner grip** (bottom-right, next to the ticker) — minimum 360×480, size is remembered |

### The Tasks tab

A lightweight task list with due-time reminders that live in `~/.zcode/widget-tasks.json`:

- **New / edit** — title, notes, optional due date & time (defaults to +1 h), a priority (Low / Medium / High), and a **Remind me at the due time** switch
- **Notifications** — at the due time macOS shows a banner (even if the widget is closed); it carries a **Mark Done** action, and clicking the banner opens the panel on the Tasks tab. First reminder asks for notification permission.
- **Overdue handling** — rows show relative due times and turn red when overdue; a task saved already-overdue reminds immediately. Stale overdue tasks are never re-announced after a relaunch.
- **Badges & glance** — the sidebar shows a red count of tasks due within 24 h; the **Z** icon's tooltip and right-click menu list due tasks
- **Organizing** — tap the circle to complete (moves to the collapsible **Completed** section, tap again to reopen), tap a row to edit, trash to delete

### The Thermal tab

- **Status** — the current macOS thermal state (Cool / Warm / Hot / Critical) from `ProcessInfo.thermalState` (raw °C needs admin rights on Apple Silicon — macOS 15 returns SMC "key not found" for every key from a normal process, so the widget deliberately uses the OS's own thermal signal + live CPU instead), sampled every 8 s
- **Heaviest processes** — real current CPU% per process (`top -l 2`, two 1-second passes), refreshed every ~16 s; ZCode-related processes get a tag
- **Heat alerts** — when pressure reaches serious/critical, or the machine sustains *fair* pressure ≥ 24 s under heavy CPU, an event is recorded naming the hot process and the chat session that was active in `~/.zcode/log/token-tail.jsonl` at that moment (session titles come from the ZCode database, read-only). Events persist to `~/.zcode/widget-thermal.json` (last 50); alerts banner only every 10 minutes per episode and notification permission is asked lazily on the first event
- **Management** — when hot: notification banner (tap → Thermal tab), red flame badge in the sidebar + Z-icon menu entry, and a cool-down card with one-click **Activity Monitor** / **open the hot chat's project** helpers

### The Captures tab

Screenshots & screen recordings you can browse, preview, and send into a live ZCode chat:

- **Capture** — **Screen** photographs the whole display the ZCode chat window is on; **Window** photographs just that window (auto-cropped). **Record** records the display until you press **Stop** — the widget hides its panel first so it never shows up in its own captures, the menu-bar icon shows a red dot while recording, and its right-click menu gains a **⏹ Stop screen recording** item. Recordings are H.264 `.mov` files.
- **Privacy blur** *(optional, off by default)* — enable **Blur sensitive areas**, then **Edit areas…** takes a one-time reference screenshot (in memory only) on which you drag boxes over anything sensitive — a credentials panel, an open password manager, your chat input. Boxes are remembered in `~/.zcode/widget-capture-settings.json` and redacted from every screenshot and recording of that screen, in your choice of **Blur** or **Pixelate** style. Screenshots are redacted in memory before anything is written to disk; recordings are post-processed after Stop (a progress row shows the export) and the unblurred raw file is hard-deleted — **unblurred originals are never kept**. Boxes are fixed to the screen, not to windows: if you move a window, drag its box along too. On the rare failure the recording is kept unblurred with a loud "saved WITHOUT blur" warning so you can delete it.
- **Voice-over narration** *(optional, off by default)* — enable **Voice-over narration (microphone)** and recordings capture your mic alongside the screen. macOS asks for microphone permission the first time (Settings → Privacy & Security → Microphone); if it's denied the hint turns amber with a deep link, and recordings continue silent rather than failing.
- **Gallery** — every capture lands in `~/.zcode/captures/` (`shot-<timestamp>.png` / `rec-<timestamp>.mov`) and appears in a thumbnail grid with duration chips on videos; select one to preview it (images full-size, videos play inline) with its date, size and actions: **Copy**, **Reveal** in Finder, **Delete** (to Trash), and **Send to chat**.
- **Send to chat** — for screenshots only: the button next to a chat picker (newest live chats first) writes the image into that chat's own `session_input` queue in `~/.zcode/cli/db/db.sqlite` — the same channel the ZCode UI itself uses, mirrored field-for-field from a real message. ZCode promotes it within a few seconds; if it doesn't (the mechanism is internal and unverified for outside writers), the widget copies the image instead and says so. Nothing is ever sent automatically — only when you click **Send to chat**. Videos can't be auto-sent; **Copy video** puts the file on your clipboard to attach manually.
- **Permission** — first use needs macOS Screen Recording permission (Settings → Privacy & Security → Screen & System Audio Recording → ZCodeWidget). The widget explains this on the tab and deep-links to the right pane; macOS may ask for your Touch ID/password, and the widget should be quit & reopened afterwards. Because the widget is ad-hoc signed, a newly built/reinstalled binary needs the grant once more.

### The Design Library tab

A searchable library of design directions — palette, typography pairing, imagery and layout guidance, page-by-page application notes (home / category / product / checkout), UI details, and reference sites — persisted to `~/.zcode/design-library.json`:

- **7 curated built-ins** — Editorial Minimal, Quiet Luxury, Brutalist Streetwear, Heritage Archive, Performance Tech, Playful DTC, and Romantic Boho: clothing-store ecommerce directions with real palettes and reference brands (COS, Toteme, Everlane · The Row, Khaite, Celine · SSENSE, Palace, END. · Carhartt WIP, RRL, Grailed · Nike, lululemon, Gymshark · Telfar, Ganni, Baggu · Free People, Sézane, Reformation)
- **Click any color swatch to copy its hex** (a toast confirms); clicking a card opens the full design brief
- **Copy brief as Markdown** — one tap exports the whole direction as a paste-ready brief for a designer, developer, or ZCode itself
- **Add your own** — **＋** opens the editor (swatch rows with live color previews, reference rows, all brief fields); built-ins can be **duplicated** to edit, deleted, and re-seeded anytime with the restore (↻) button
- **Filter** with the tag chips (Minimal / Luxury / Streetwear / Heritage / Performance / Playful / Boho — plus any tags you invent) or search across names, taglines, and typography

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

### Database backups

`scripts/db-backup.sh` dumps a project's Supabase/Postgres database to a local backup — the piece the widget deliberately can't do itself (the widget never reads `.env` values; this script does, and passes the connection straight to `pg_dump` without ever printing it):

```bash
./scripts/db-backup.sh /path/to/project        # one or more project dirs
```

- Backs up to `~/db-backups/<project>-<timestamp>.dump` — pg_dump custom format, compressed, includes the `public`, `auth`, and `storage` schemas
- Keeps the newest 14 dumps per project (override with `DB_BACKUP_KEEP` / `DB_BACKUP_DIR`)
- Prefers `postgresql@17`'s pg_dump when installed, so newer Supabase servers (Postgres 15/17) dump fine even if the default pg_dump is older
- Secrets-safe: the connection URL is read from the project's `.env` into a variable and passed straight to `pg_dump` — never echoed, logged, or printed; failures print a reason, never the URL

Restore:

```bash
pg_restore --clean --if-exists --no-owner --no-privileges \
  -d "<connection-url>" ~/db-backups/<file>.dump
```

## Project structure

```
zcode-widget/
├── install.sh                # One-command installer (Option B)
├── project.yml               # XcodeGen manifest (GRDB dependency)
├── Package.swift             # SwiftPM manifest
├── agents/
│   └── database-expert.md    # ZCode subagent: database expert behind the Database tab
├── scripts/
│   └── db-backup.sh          # Postgres backup helper (pg_dump custom format + rotation)
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
│   │   ├── DesignLibraryStore.swift # Design directions (~/.zcode/design-library.json)
│   │   ├── TaskStore.swift          # Task items (~/.zcode/widget-tasks.json)
│   │   ├── TaskReminderManager.swift # Local notifications + due-task scanner
│   │   ├── WidgetSettingsStore.swift # Daily budget + pinned folders (~/.zcode/widget-settings.json)
│   │   ├── ThermalMonitor.swift      # Thermal pressure + CPU sampling, heat alerts
│   │   ├── CaptureStore.swift        # ~/.zcode/captures library (scan, thumbs, durations)
│   │   ├── CaptureRecorder.swift     # Screenshot + screen-recording engine (TCC-gated, mic voice-over)
│   │   ├── CaptureOptionsStore.swift # Blur + voice-over toggles & areas (~/.zcode/widget-capture-settings.json)
│   │   ├── PrivacyRedactor.swift     # Blur/pixelate redaction for stills + video export pipeline
│   │   ├── ChatSender.swift          # Send-to-chat via the session_input queue + clipboard fallback
│   │   └── ActivityTicker.swift    # Latest-call ticker state
│   ├── Database/
│   │   ├── ProjectDbScanner.swift  # Discovers projects + parses SQL → tables/policies/functions/triggers
│   │   └── ProjectDbModels.swift   # Inventory structs
│   ├── Discovery/
│   │   ├── SkillScanner.swift   # Scans ~/.zcode/skills/ for SKILL.md
│   │   └── PluginScanner.swift  # Reads installed_plugins.json + config.json
│   ├── UI/
│   │   ├── ContentView.swift    # Sidebar + section switcher (11 sections)
│   │   ├── TokensView.swift     # Stats cards + chart + streak + turn list
│   │   ├── SkillsView.swift     # Searchable skill picker + copy slash command
│   │   ├── PluginsView.swift    # Searchable plugin picker + copy slash command
│   │   ├── ProvidersView.swift  # Provider list + editors (provider, model)
│   │   ├── ReportView.swift     # Weekly shareable card + heatmap
│   │   ├── PromptsView.swift    # Prompt enhancer + library
│   │   ├── DesignLibraryView.swift # Design-direction library (briefs, swatches, export)
│   │   ├── DesignSystem/        # Shared design tokens (Theme) + reusable components
│   │   ├── DatabaseView.swift   # Per-project database dashboard
│   │   ├── TasksView.swift      # Task list + editor (due dates, priorities)
│   │   ├── ThermalView.swift    # Heat status, cool-down helpers, alerts history
│   │   ├── CapturesView.swift   # Capture bar, privacy & voice-over options, gallery, send-to-chat
│   │   ├── PrivacyAreaEditorSheet.swift # Draw blur areas on an in-memory reference screenshot
│   │   ├── SettingsView.swift   # Settings sheet (daily budget)
│   │   ├── ActivityTickerBar.swift  # Live bottom ticker strip
│   │   └── ToastView.swift      # Copy-to-clipboard feedback toast
│   └── Window/
│       ├── FloatingPanelController.swift  # KeyablePanel, position + size restore/clamp
│       └── ResizeGripView.swift           # Bottom-right drag-to-resize grip (borderless panels have no edges)
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
- All data paths are read from the current user's home directory; the widget never writes anywhere except provider-config edits (with backup) in `~/.zcode/v2/`, its own task file in `~/.zcode/widget-tasks.json`, the capture-options file `~/.zcode/widget-capture-settings.json`, and the captures folder `~/.zcode/captures/` (plus the rare user-clicked **Send to chat** queue insert in `~/.zcode/cli/db/db.sqlite`).

## License

MIT — do whatever you like; attribution appreciated.
