<p align="center">
  <img src="Sources/NavRead/Resources/AppIconBase.png" width="128" height="128" alt="NavRead icon" />
</p>

<h1 align="center">NavRead</h1>

<p align="center">
  A native macOS commonplace-book app for capturing, organizing, and revisiting the quotes that matter.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" />
  <img src="https://img.shields.io/badge/swift-6.2-orange" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
</p>

---

## What is NavRead?

NavRead turns your reading into a searchable, organized library. Every quote you save lives inside a book, chapter, and page — never just a loose snippet. Add books by title and NavRead fetches metadata and covers automatically, scaffolds chapters with AI, and lets you capture quotes from text, PDFs, images (via OCR), or the web.

### Key Features

- **Book-first organization** — quotes are always anchored to a book, chapter, and page
- **Auto metadata & covers** — Google Books and Open Library lookup on book creation
- **AI chapter scaffolds** — chapters are drafted automatically and are fully editable
- **Multi-source capture** — paste text, import images/PDFs (Vision OCR), or extract from web URLs
- **Full-text search** — find anything by title, author, quote text, tag, or note
- **Export anywhere** — Markdown, JSON, CSV to clipboard or file, or directly to Apple Notes
- **Glassmorphism UI** — frosted glass panels, spring animations, adaptive light/dark mode
- **Local-first** — all data stays on your Mac in a SQLite database, no cloud required
- **Codex AI integration** — optional OpenAI Codex connection for richer chapter scaffolds and contextual AI chat

## Screenshots

> *Build and run to see the full UI — glassmorphism panels, animated book covers, quote timeline, AI palette, and more.*

## Getting Started

### Requirements

- macOS 15.0 (Sequoia) or later
- Swift 6.2+ toolchain
- Xcode Command Line Tools

### Build & Run

```bash
git clone https://github.com/psagar29/navread.git
cd navread
./script/build_and_run.sh
```

This builds the Swift package, assembles a `.app` bundle under `dist/`, and launches NavRead.

### Other build modes

```bash
./script/build_and_run.sh --verify     # Build, launch, confirm the process started
./script/build_and_run.sh --logs       # Build, launch, stream system logs
./script/build_and_run.sh --telemetry  # Build, launch, stream subsystem telemetry
```

## Architecture

```
NavRead/
├── App/             # @main entry point, window & menu config
├── Models/          # Core data structures (Book, Chapter, Quote, Capture, etc.)
├── Views/           # SwiftUI views — sidebar, workspace, inspector, sheets
├── Stores/          # State management (NavReadStore) and SQLite persistence
├── Services/        # Book metadata lookup, cover cache, OCR, AI integration
├── Support/         # Design system (GlassUI), color utilities, settings, paths
├── Resources/       # App icon assets
└── Tests/           # Unit tests
```

**Design pattern:** MVVM with `ObservableObject` reactive state  
**Persistence:** Direct SQLite3 bindings (no ORM)  
**Concurrency:** Swift actor model for AI and OAuth services

## Data Storage

| What | Where |
|------|-------|
| Database | `~/Library/Application Support/NavRead/NavRead.sqlite` |
| Book covers | `~/Library/Application Support/NavRead/Assets/Covers/` |
| Imported captures | `~/Library/Application Support/NavRead/Assets/Captures/` |
| OAuth tokens | Local credential file with `0600` permissions |

NavRead does not use iCloud, Keychain, or any cloud service. All data stays local.

## Codex AI (Optional)

NavRead optionally connects to OpenAI Codex for:
- Richer chapter scaffolding on book import
- Quote candidate extraction from captures
- Contextual AI chat scoped to a book, chapter, or quote

Sign in via **Settings → Codex → Sign In**. The app works fully offline without it — chapter scaffolds fall back to a local template.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Author

**Pranav Sagar** — [GitHub](https://github.com/psagar29)
