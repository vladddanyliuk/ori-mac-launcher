# Compatibility validation

## Automated validation

The repository CI covers everything that can be tested without a real signed-in Steam session:
- shell syntax;
- ShellCheck;
- one-command interface invariants;
- Steam App ID/manifest parsing;
- config JSON;
- reset-path safety;
- basic secret-log scanning.

## Real-device acceptance matrix

A real gameplay session is still required before claiming the game itself is verified playable.

| Item | Implementation | Real-device verification |
| --- | --- | --- |
| Apple Silicon bootstrap | done | pending |
| Windows Steam install | done | pending |
| Ori App ID 1057090 launch | done | pending |
| DX11 → DXMT path | configured | pending |
| Keyboard | runtime path ready | pending |
| Audio | runtime path ready | pending |
| DualSense/Xbox controller | runtime path ready | pending |
| Save/load | Steam/Wine path ready | pending |
| Steam Cloud/achievements | Steam launch path ready | pending |
| 60 FPS target | not claimable without hardware | pending |

We deliberately do not fabricate FPS, controller, save/load, or crash-free results from CI. A human or dedicated Mac test machine must complete the final gameplay acceptance run.
