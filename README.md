# Ori Mac Launcher

A one-command Apple Silicon macOS launcher for the Windows versions of the Ori games.

## Quick start

```bash
git clone https://github.com/vladddanyliuk/ori-mac-launcher.git
cd ori-mac-launcher
./ori
```

`./ori` auto-detects an installed Ori title in the private Windows Steam prefix and launches it with the matching game profile.

Detection order:
1. Ori and the Blind Forest — Steam 261570
2. Ori and the Blind Forest: Definitive Edition — Steam 387290
3. Ori and the Will of the Wisps — Steam 1057090

You can also choose explicitly:

```bash
./ori blind
./ori blind-de
./ori wotw
```

## What the launcher handles

- Apple Silicon/macOS/Rosetta checks
- pinned WhiskyWine 3.1.1 runtime
- DXMT 0.80 Direct3D 11 → Metal path
- isolated Wine prefix
- Windows Steam bootstrap/login
- installed-game auto-detection across Steam library paths
- per-game executable/App ID profiles
- forced Unity 1920×1080 fullscreen baseline
- Retina scaling disabled for the gameplay path
- ESYNC-only scheduling
- CoreAudio + stability-oriented DirectSound buffer
- diagnostics, logs and safe reset

## Commands

```text
./ori              auto-detect installed Ori and launch
./ori blind        launch Ori and the Blind Forest
./ori blind-de     launch Definitive Edition
./ori wotw         launch Will of the Wisps
./ori --steam      open Windows Steam
./ori --doctor     diagnostics
./ori --game-logs [blind|blind-de|wotw]
                   print newest Unity output_log.txt / Player.log
./ori --self-test  validate Wine + DXMT
./ori --logs       reveal logs
./ori --reset      delete only OriMac's private prefix after confirmation
```

## Data locations

```text
~/Library/Application Support/OriMac/
~/Library/Logs/OriMac/
```

OriMac never edits the native macOS Steam installation.
