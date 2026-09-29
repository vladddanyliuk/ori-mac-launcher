# Compatibility validation

## Pre-validation evidence

The renderer choice is not arbitrary:

- current CodeWeavers compatibility data rates **Ori and the Will of the Wisps** as running well on macOS through a Wine/CrossOver-style compatibility layer;
- DXMT compatibility databases specifically report Ori on the DXMT path and reference the upstream fix for the historical missing-character rendering bug;
- older CrossOver reports showed that the game itself could run at 60 FPS on Apple Silicon, while the historical invisible-Ori bug was renderer-related.

That evidence is useful for choosing the stack, but it is **not** recorded here as if OriMac itself has already passed a real-device test.

## Automated/static validation

The repository contains tests for everything that can be validated without signing into Steam and playing the game:

- shell syntax;
- executable one-command entry point;
- game-profile parsing;
- pinned runtime/checksum contract;
- path/reset safety;
- Steam App ID and manifest parsing;
- idempotent runtime bootstrap decisions;
- prefix schema adoption/migration behavior;
- secret/logging safety.

`./ori --self-test` additionally performs a real local runtime check without requiring Steam login:

1. downloads/verifies the pinned runtime if needed;
2. initializes the private Wine prefix;
3. confirms Wine can execute a Windows command;
4. confirms the required DXMT DLLs are deployed.

## Real-device acceptance matrix

The final end-to-end gameplay pass must happen on a real Apple Silicon Mac with a Steam account that owns the game.

| Item | Implementation | Real-device verification |
| --- | --- | --- |
| Apple Silicon bootstrap | done | pending |
| Runtime SHA verification | done | pending execution |
| Wine prefix creation | done | pending execution |
| Windows Steam install | done | pending execution |
| Steam login persistence | implemented | pending |
| Ori App ID 1057090 detection | done | pending |
| Ori process-start detection | done | pending |
| DX11 → DXMT 0.80 path | configured | pending |
| Keyboard input | runtime path ready | pending |
| Audio output | runtime path ready | pending |
| DualSense/Xbox controller | runtime path ready | pending |
| Fullscreen/windowed | runtime path ready | pending |
| Save/load | Steam/Wine path ready | pending |
| Steam Cloud/achievements | Steam launch path ready | pending |
| 60 FPS target | cannot be claimed without hardware | pending |
| 15-minute crash-free gameplay | cannot be claimed without gameplay | pending |

## Acceptance procedure

When the development branch is ready for the first hardware pass:

1. clone the repository;
2. run only `./ori`;
3. sign into the Windows Steam window and install Ori when prompted;
4. run `./ori` again if the first session was used only for installation;
5. play for at least 15 minutes and create/reload a save;
6. test keyboard and at least one controller if available;
7. record Mac model, macOS version, resolution and observed FPS;
8. attach `./ori --doctor` output if anything fails.

The project deliberately does not fabricate hardware results. This document becomes the permanent measured compatibility record after that pass.
