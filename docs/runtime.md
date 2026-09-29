# Runtime architecture

## Selected stack

OriMac uses the maintained `frankea/Whisky` WhiskyWine runtime as the low-level Wine distribution, but **does not require Whisky.app or its GUI**.

Pinned components:

- WhiskyWine runtime: `3.1.1`
- Runtime archive SHA-256: `01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3`
- DXMT: `0.80`
- DXVK payload: `1.10.3`
- Prefix mode: Windows 10
- Target: Apple Silicon, macOS Sequoia 15+

Ori is a DirectX 11 game, so **DXMT is the primary renderer**.

## Why DXMT

### DXMT — selected

Path:

```text
Ori DX11 → DXMT → Metal → Apple GPU
```

DXMT is the most direct fit for this launcher: it targets Direct3D 11 and translates to Metal without adding a Vulkan hop. The pinned WhiskyWine runtime already carries the required x64/x32 payload.

OriMac deploys these DLLs into its private prefix:

```text
d3d11.dll
dxgi.dll
d3d10core.dll
winemetal.dll
```

and applies:

```text
dxgi=n,b;d3d10core=n,b;d3d11=n,b;winemetal=b;d3d12=
```

### DXVK/MoltenVK — fallback

Path:

```text
Ori DX11 → DXVK → Vulkan → MoltenVK → Metal
```

The pinned runtime contains DXVK as a fallback, but OriMac does not select it by default because DXMT removes one translation layer for this DX11-specific project. The game profile keeps the fallback version recorded so a future compatibility switch does not require changing the public CLI.

### Apple D3DMetal / GPTK — not the default

D3DMetal is technically attractive, but making it the default would complicate redistribution/provisioning because Apple components have their own licensing and installation constraints. OriMac deliberately does not copy proprietary Apple frameworks into this repository.

The provider boundary allows a future optional GPTK/D3DMetal backend without changing `./ori`.

## Headless provisioning

`./ori` performs the runtime bootstrap itself:

1. downloads the exact pinned `Libraries.tar.gz` release;
2. computes SHA-256 and fails closed on a mismatch;
3. extracts into `~/Library/Application Support/OriMac/runtime/`;
4. initializes `~/Library/Application Support/OriMac/prefix/` using `wineboot --init`;
5. records a prefix schema version;
6. deploys DXMT into the prefix;
7. installs Windows Steam into that same isolated prefix.

No Homebrew command, Whisky GUI, manual Wine command, or environment-variable editing is required.

## Sources

Runtime archive template:

```text
https://github.com/frankea/Whisky/releases/download/v<VERSION>/Libraries.tar.gz
```

Steam installer:

```text
https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe
```

The pinned runtime values mirror the provider's published `WhiskyWineVersion.plist`.

## Game profile

All Ori-specific choices live in `config/ori.json`, including:

- Steam App ID `1057090`;
- expected executable `oriwotw.exe`;
- runtime and renderer versions;
- Wine environment variables;
- DLL overrides;
- launch mode and arguments;
- documented workarounds.

The shell modules consume this profile rather than requiring users to edit environment variables.

## Redistribution and ownership

OriMac does not vendor or commit:

- Steam;
- Ori game files;
- CrossOver binaries;
- Apple proprietary graphics frameworks.

Users download the compatibility runtime from its upstream distribution and Steam from Valve. Users must use their own Steam account/license for Ori.

## Provider boundary

Provider-specific runtime code lives in `lib/whisky.sh`. The user-facing contract remains:

```bash
./ori
```

so the low-level Wine/graphics provider can be replaced later without changing the launcher interface.
