#!/usr/bin/env bash

# Runtime provider: frankea/Whisky + its open-source WhiskyWine distribution.
# We intentionally install the runtime ourselves so first-run bootstrap remains
# headless and the public contract stays: ./ori

WHISKY_APP="/Applications/Whisky.app"
WHISKY_CLI="$WHISKY_APP/Contents/Resources/WhiskyCmd"
WHISKY_BREW_CASK="frankea/whisky/whisky"

WHISKY_BUNDLE_ID="com.franke.Whisky"
WHISKY_SUPPORT="${HOME}/Library/Application Support/${WHISKY_BUNDLE_ID}"
WHISKY_LIBRARIES="$WHISKY_SUPPORT/Libraries"
WHISKY_WINE="$WHISKY_LIBRARIES/Wine/bin/wine64"
WHISKY_WINESERVER="$WHISKY_LIBRARIES/Wine/bin/wineserver"
WHISKY_VERSION_PLIST_URL="https://frankea.github.io/Whisky/WhiskyWineVersion.plist"
WHISKY_RELEASE_BASE="https://github.com/frankea/Whisky/releases/download"

ORI_PREFIX="$APP_SUPPORT_DIR/prefix"
RUNTIME_STATE="$STATE_DIR/runtime.env"

ensure_homebrew() {
  if command_exists brew; then
    return 0
  fi

  warn "Homebrew is required to install the signed Whisky application."
  if ! confirm "Install Homebrew now?"; then
    error "Cannot provision the runtime without Homebrew."
    exit 3
  fi

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  command_exists brew || {
    error "Homebrew installation completed but brew is unavailable."
    exit 3
  }
}

ensure_whisky_app() {
  if [[ -d "$WHISKY_APP" ]]; then
    return 0
  fi

  ensure_homebrew
  info "Installing the maintained Whisky fork..."
  brew install --cask "$WHISKY_BREW_CASK"

  [[ -d "$WHISKY_APP" ]] || {
    error "Whisky installation did not produce $WHISKY_APP"
    exit 4
  }
}

plist_value() {
  local plist="$1" key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null
}

runtime_is_usable() {
  [[ -x "$WHISKY_WINE" ]] &&
  [[ -f "$WHISKY_LIBRARIES/WhiskyWineVersion.plist" ]]
}

fetch_runtime_metadata() {
  local plist="$DOWNLOAD_DIR/WhiskyWineVersion.plist"
  info "Fetching WhiskyWine runtime metadata..."
  curl --fail --location --retry 3 --silent --show-error     "$WHISKY_VERSION_PLIST_URL" -o "$plist.tmp"
  mv "$plist.tmp" "$plist"

  local version sha
  version="$(plist_value "$plist" version || true)"
  sha="$(plist_value "$plist" sha256 || true)"

  if [[ -z "$version" ]]; then
    error "Runtime metadata does not contain a version."
    exit 4
  fi

  printf 'RUNTIME_VERSION=%q\n' "$version" > "$RUNTIME_STATE"
  printf 'RUNTIME_SHA256=%q\n' "$sha" >> "$RUNTIME_STATE"
}

load_runtime_state() {
  if [[ -f "$RUNTIME_STATE" ]]; then
    # shellcheck disable=SC1090
    source "$RUNTIME_STATE"
  fi
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

install_runtime_headless() {
  fetch_runtime_metadata
  load_runtime_state

  local archive="$DOWNLOAD_DIR/Libraries-${RUNTIME_VERSION}.tar.gz"
  local url="$WHISKY_RELEASE_BASE/v${RUNTIME_VERSION}/Libraries.tar.gz"

  if [[ ! -s "$archive" ]]; then
    info "Downloading WhiskyWine ${RUNTIME_VERSION} (~hundreds of MB)..."
    curl --fail --location --retry 3 --progress-bar "$url" -o "$archive.tmp"
    mv "$archive.tmp" "$archive"
  fi

  if [[ -n "${RUNTIME_SHA256:-}" ]]; then
    local actual
    actual="$(sha256_file "$archive")"
    if [[ "${actual,,}" != "${RUNTIME_SHA256,,}" ]]; then
      rm -f "$archive"
      error "WhiskyWine checksum mismatch."
      error "Expected: $RUNTIME_SHA256"
      error "Actual:   $actual"
      exit 4
    fi
  else
    warn "Runtime metadata did not publish a SHA-256; HTTPS transport is the only integrity layer."
  fi

  info "Installing WhiskyWine runtime headlessly..."
  mkdir -p "$WHISKY_SUPPORT"
  rm -rf "$WHISKY_LIBRARIES"

  # The upstream archive contains Libraries/ at its root.
  tar -xzf "$archive" -C "$WHISKY_SUPPORT"

  if ! runtime_is_usable; then
    error "Runtime extraction completed but wine64/version metadata are missing."
    exit 4
  fi
}

ensure_runtime() {
  ensure_whisky_app
  if runtime_is_usable; then
    return 0
  fi
  install_runtime_headless
}

wine_env() {
  export WINEPREFIX="$ORI_PREFIX"
  export WINEDEBUG="${WINEDEBUG:--all}"
  export WINEESYNC=1
  export WINEMSYNC=1
  export CX_ROOT="$WHISKY_LIBRARIES/Wine"
  export PATH="$WHISKY_LIBRARIES/Wine/bin:$PATH"

  # Prefer DXMT for DX11 when present. WhiskyWine ships the payload and Wine
  # can resolve its native D3D DLLs from the runtime.
  if [[ -d "$WHISKY_LIBRARIES/DXMT" ]]; then
    export WINEDLLOVERRIDES="d3d11,dxgi=n,b;${WINEDLLOVERRIDES:-}"
  fi
}

wine_run() {
  wine_env
  "$WHISKY_WINE" "$@"
}

wineserver_wait() {
  wine_env
  "$WHISKY_WINESERVER" -w
}

prefix_is_initialized() {
  [[ -f "$ORI_PREFIX/system.reg" ]] &&
  [[ -d "$ORI_PREFIX/drive_c/windows" ]]
}

ensure_ori_bottle() {
  mkdir -p "$ORI_PREFIX"
  if prefix_is_initialized; then
    return 0
  fi

  info "Creating Ori Windows prefix..."
  wine_env
  "$WHISKY_WINE" wineboot --init
  wineserver_wait

  prefix_is_initialized || {
    error "Wine prefix initialization failed."
    exit 5
  }

  # Windows 10 mode. Ignore failure here only if the runtime does not expose winecfg
  # as a separate executable; Wine defaults are still usable.
  wine_run reg add 'HKCU\Software\Wine' /v Version /d win10 /f >/dev/null 2>&1 || true

  printf 'PREFIX_VERSION=1\n' > "$STATE_DIR/prefix.env"
  info "Prefix ready: $ORI_PREFIX"
}

reset_bottle() {
  init_paths
  if [[ ! -d "$ORI_PREFIX" ]]; then
    info "No OriMac prefix exists. Nothing to reset."
    return 0
  fi

  if ! confirm "Delete the OriMac prefix? Steam and Ori files inside it will be removed."; then
    info "Reset cancelled."
    return 0
  fi

  if [[ -x "$WHISKY_WINESERVER" ]]; then
    wine_env
    "$WHISKY_WINESERVER" -k >/dev/null 2>&1 || true
  fi

  rm -rf "$ORI_PREFIX"
  rm -f "$STATE_DIR/prefix.env"
  info "Prefix reset complete. Run ./ori to recreate it."
}
