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
1. downloads the pinned `Libraries.tar.gz` directly from the maintained WhiskyWine release;
2. verifies the exact pinned SHA-256 digest;
3. extracts the runtime into OriMac's private Application Support directory;
4. initializes OriMac's own prefix with `wineboot --init`;
5. deploys the pinned DXMT DLL set into the prefix.

The launcher therefore owns its prefix and state while the Wine/graphics implementation remains replaceable.

## Runtime sources

Pinned runtime: `3.1.1`  
Pinned SHA-256: `01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3`  
Pinned DXMT: `0.80`  
Pinned DXVK payload: `1.10.3`

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
