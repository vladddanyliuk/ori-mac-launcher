# Runtime architecture

## Selected MVP stack

OriMac uses the actively maintained `frankea/Whisky` distribution as its Wine/DX11 runtime provider.

The maintained fork currently documents:
- Wine 11.x;
- DXMT for native Direct3D 11 → Metal translation;
- DXVK/MoltenVK as fallback;
- Apple Silicon support;
- Steam launcher compatibility.

Ori itself is a DirectX 11 title, so DXMT is the preferred backend for the MVP.

## Headless provisioning

OriMac does **not** depend on Whisky's first-run GUI.

`./ori`:
1. installs the signed/notarized maintained Whisky app via its qualified Homebrew tap when missing;
2. fetches the provider's `WhiskyWineVersion.plist`;
3. derives the matching `Libraries.tar.gz` release URL;
4. verifies SHA-256 when the provider metadata publishes it;
5. extracts the runtime into the same Application Support location expected by WhiskyWine;
6. initializes OriMac's own prefix with `wineboot --init`.

The launcher therefore owns its prefix and state while the Wine/graphics implementation remains replaceable.

## Runtime sources

Metadata:
`https://frankea.github.io/Whisky/WhiskyWineVersion.plist`

Archive template:
`https://github.com/frankea/Whisky/releases/download/v<VERSION>/Libraries.tar.gz`

Steam installer:
`https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe`

## Redistribution

OriMac does not vendor or commit:
- CrossOver binaries;
- Steam;
- Ori game files;
- Apple proprietary framework payloads.

Runtime components are fetched from their upstream distribution at setup time. This avoids pretending that our repository grants redistribution rights it does not own.

## Runtime/provider boundary

All provider-specific code lives in `lib/whisky.sh`. The public interface remains `./ori`, so the runtime can later be replaced without changing user-facing commands.
