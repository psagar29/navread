<p align="center">
  <img src="Sources/NavRead/Resources/AppIconBase.png" width="128" height="128" alt="NavRead icon" />
</p>

<h1 align="center">NavRead</h1>

<p align="center">
  A simple Mac app for saving the lines, pages, and ideas you never want to lose.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" />
  <img src="https://img.shields.io/badge/swift-6.2-orange" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
</p>

<p align="center">
  <a href="https://github.com/psagar29/navread/releases/latest/download/NavRead.dmg"><strong>Download NavRead for Mac</strong></a>
</p>

---

## What is NavRead?

NavRead is a personal reading desk for your Mac. It helps you save favorite quotes, passages, notes, screenshots, PDFs, and web links in one clean library.

Instead of dumping quotes into a notes app, NavRead keeps everything organized by book, chapter, and page. Add a book title, and NavRead looks up the book details and cover for you. Then you can save quotes manually, pull text from PDFs or images, ask AI to clean messy OCR, and export polished quote cards when you want to share something.

### Key Features

- **Add books quickly** - type a title, and NavRead fetches the cover and book details automatically.
- **Save quotes with context** - keep quotes attached to the right book, chapter, and page.
- **Capture from anywhere** - paste text, import PDFs, drop images, use OCR, or extract from web links.
- **Ask AI for help** - clean OCR, classify notes, explain passages, create tags, and find quote candidates.
- **Search your reading** - find books, authors, quotes, tags, and notes in seconds.
- **Share beautiful quote cards** - export square, story, or landscape cards for social media.
- **Private by default** - your library is stored locally on your Mac.
- **Works without AI** - core reading and quote capture features work even when Codex is not connected.

## Download

Download the latest Mac installer:

**[Download NavRead.dmg](https://github.com/psagar29/navread/releases/latest/download/NavRead.dmg)**

Open the DMG, drag `NavRead.app` into `Applications`, then launch NavRead from Launchpad or Spotlight.

## Screenshots

> Screenshots coming soon.

## For Developers

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
Book cover images are runtime cache files and should never be committed to the repo.

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
