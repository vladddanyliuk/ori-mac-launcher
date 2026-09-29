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
2. installs the maintained Whisky app if its runtime is not present;
3. downloads and verifies the WhiskyWine runtime metadata/archive;
4. creates a private Wine prefix under OriMac's own Application Support folder;
5. installs the Windows Steam client;
6. opens Steam for the unavoidable account sign-in/game purchase/install UI;
7. once App ID `1057090` is installed, launches Ori directly on subsequent `./ori` runs.

There is no first-run Whisky GUI/bottle setup dependency.

## Commands

```text
./ori            bootstrap / launch Ori
./ori --steam    open Windows Steam
./ori --doctor   diagnostics
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

The shared WhiskyWine runtime is stored by its upstream provider under:

```text
~/Library/Application Support/com.franke.Whisky/Libraries/
```

## Requirements

- Apple Silicon Mac
- macOS Sequoia 15 or newer
- Internet connection
- Steam account that owns Ori and the Will of the Wisps

Rosetta is installed by macOS when required. Homebrew is used only to install the signed/notarized maintained Whisky application; OriMac provisions the Wine runtime itself without requiring the Whisky GUI.

## Development

```bash
./tests/test.sh
```

CI validates shell syntax, ShellCheck, state-machine decisions, manifest parsing and safety invariants. Real gameplay validation is tracked separately because GitHub's CI runners cannot interactively sign into Steam or play the game.
