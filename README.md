# Ori Mac Launcher

A tiny game-specific compatibility launcher for **Ori and the Will of the Wisps** on Apple Silicon macOS.

## Quick start

```bash
git clone https://github.com/vladddanyliuk/ori-mac-launcher.git
cd ori-mac-launcher
./ori
```

That is the public contract: **one command** for bootstrap and later launches.

On the first run OriMac provisions its runtime, creates an isolated `OriMac` bottle and installs the Windows Steam client. Steam login and installing the game are still normal interactive Steam UI steps. After Ori is installed, `./ori` launches Steam App ID `1057090` directly.

> Current MVP note: the selected Whisky runtime requires its GUI to finish the initial bottle bootstrap once. `./ori` opens it automatically and waits. We are keeping the command contract stable while we remove this runtime limitation.

## Commands

```text
./ori            bootstrap / launch Ori
./ori --steam    open Windows Steam
./ori --doctor   diagnostics
./ori --logs     reveal logs
./ori --reset    delete the managed Ori bottle after confirmation
```

## Data locations

```text
~/Library/Application Support/OriMac/
~/Library/Logs/OriMac/
```

The macOS Steam installation is not modified.

## Requirements

- Apple Silicon Mac
- macOS Sonoma 14 or newer
- Internet connection
- A Steam account that owns Ori and the Will of the Wisps

Rosetta and the runtime are handled by the bootstrap flow. Homebrew is currently used for runtime provisioning; if it is missing, `./ori` asks before installing it.

## Development

```bash
./tests/test.sh
```

See `docs/runtime.md` for the runtime boundary and known first-run limitation.
