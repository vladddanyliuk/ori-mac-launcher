# Runtime decision

## MVP provider

OriMac currently provisions the actively maintained `frankea/Whisky` fork through Homebrew and calls its embedded `WhiskyCmd` directly. This keeps OriMac small while giving us a maintained Wine wrapper with DX11 translation support on Apple Silicon.

The original `Whisky-App/Whisky` project is archived and must not be used as the default runtime source.

## Why this is not the final runtime architecture

The long-term goal is to own the launcher and game profile while keeping the compatibility layer replaceable. `lib/whisky.sh` is therefore a provider boundary. A future provider can download a pinned Wine/GPTK-compatible runtime directly and remove the Homebrew/Whisky dependency without changing the public `./ori` interface.

## Security / redistribution

OriMac does not vendor Apple D3DMetal or proprietary CrossOver binaries. It does not redistribute Steam or Ori. Steam is downloaded from Valve's HTTPS installer endpoint at runtime and the user signs in with their own account.

## Current first-run limitation

Whisky's CLI can create bottle metadata, but its current implementation asks the GUI to finish bootstrapping a new Wine prefix. Therefore the MVP opens Whisky once during the first `./ori` run and waits for the user to finish that initializer. Subsequent launches are CLI-driven.

This limitation is tracked as runtime work and should be removed before calling the one-command bootstrap ticket fully complete.
