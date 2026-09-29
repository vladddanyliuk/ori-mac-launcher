# Ori Mac Launcher

A game-specific compatibility launcher for **Ori and the Will of the Wisps** on Apple Silicon macOS.

## Quick start

```bash
git clone https://github.com/vladddanyliuk/ori-mac-launcher.git
cd ori-mac-launcher
./ori
```

**That is the entire setup/launch interface.** The same command bootstraps the runtime on a fresh Mac and launches Ori on later runs.

OriMac performs these steps automatically:
1. checks Apple Silicon/macOS/Rosetta;
2. downloads the pinned WhiskyWine `3.1.1` runtime directly from its maintained upstream release;
3. verifies the pinned SHA-256 before extracting anything;
4. creates a private Wine prefix and deploys DXMT `0.80` for DirectX 11 → Metal;
5. installs the Windows Steam client;
6. opens Steam for the unavoidable account sign-in/game purchase/install UI;
7. once App ID `1057090` is installed, launches Ori directly on subsequent `./ori` runs.

There is no first-run Whisky GUI/bottle setup dependency.

## Commands

```text
./ori            bootstrap / launch Ori
./ori --steam    open Windows Steam
./ori --doctor   diagnostics
./ori --self-test validate Wine + DXMT without Steam login
./ori --logs     reveal logs
./ori --reset    delete only OriMac's private prefix after confirmation
```

## Data locations

```text
~/Library/Application Support/OriMac/
├── prefix/
├── downloads/
├── state/
└── config/

~/Library/Logs/OriMac/
```

OriMac never edits the native macOS Steam installation.

The pinned runtime is private to OriMac:

```text
~/Library/Application Support/OriMac/runtime/Libraries/
```

## Requirements

- Apple Silicon Mac
- macOS Sequoia 15 or newer
- Internet connection
- Steam account that owns Ori and the Will of the Wisps

Rosetta is installed by macOS when required. No Homebrew or Whisky GUI is required. OriMac downloads the pinned runtime archive directly and keeps it inside its own Application Support directory.

## Development

```bash
./tests/test.sh
```

CI validates shell syntax, ShellCheck, state-machine decisions, manifest parsing and safety invariants. Real gameplay validation is tracked separately because GitHub's CI runners cannot interactively sign into Steam or play the game.
