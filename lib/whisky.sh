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
WHISKY_RELEASE_BASE="https://github.com/frankea/Whisky/releases/download"

# Pinned known upstream runtime metadata from frankea/Whisky.
# Do not silently float to a newer runtime: reproducibility beats surprise upgrades.
RUNTIME_VERSION="3.1.1"
RUNTIME_SHA256="01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3"
RUNTIME_DXMT_VERSION="0.80"
RUNTIME_DXVK_VERSION="1.10.3"

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

write_runtime_state() {
  printf 'RUNTIME_VERSION=%q\n' "$RUNTIME_VERSION" > "$RUNTIME_STATE"
  printf 'RUNTIME_SHA256=%q\n' "$RUNTIME_SHA256" >> "$RUNTIME_STATE"
  printf 'RUNTIME_DXMT_VERSION=%q\n' "$RUNTIME_DXMT_VERSION" >> "$RUNTIME_STATE"
  printf 'RUNTIME_DXVK_VERSION=%q\n' "$RUNTIME_DXVK_VERSION" >> "$RUNTIME_STATE"
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
  write_runtime_state
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
    actual="$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')"
    local expected
    expected="$(printf '%s' "$RUNTIME_SHA256" | tr '[:upper:]' '[:lower:]')"
    if [[ "$actual" != "$expected" ]]; then
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

  if [[ -d "$WHISKY_LIBRARIES/DXMT" ]]; then
    export WINEDLLOVERRIDES="dxgi=n,b;d3d10core=n,b;d3d11=n,b;winemetal=b;d3d12=;${WINEDLLOVERRIDES:-}"
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
  [[ -d "$ORI_PREFIX/drive_c/windows/system32" ]]
}

deploy_dxmt() {
  local payload="$WHISKY_LIBRARIES/DXMT"
  local system32="$ORI_PREFIX/drive_c/windows/system32"
  local syswow64="$ORI_PREFIX/drive_c/windows/syswow64"
  local dll

  [[ -d "$payload/x64" ]] || {
    error "Pinned runtime is missing the DXMT x64 payload."
    exit 5
  }

  for dll in d3d11.dll dxgi.dll d3d10core.dll winemetal.dll; do
    [[ -f "$payload/x64/$dll" ]] || {
      error "DXMT payload is incomplete: missing x64/$dll"
      exit 5
    }
    cp -f "$payload/x64/$dll" "$system32/$dll"
  done

  if [[ -d "$syswow64" && -d "$payload/x32" ]]; then
    for dll in d3d11.dll dxgi.dll d3d10core.dll winemetal.dll; do
      [[ -f "$payload/x32/$dll" ]] || {
        error "DXMT payload is incomplete: missing x32/$dll"
        exit 5
      }
      cp -f "$payload/x32/$dll" "$syswow64/$dll"
    done
  fi

  printf 'DXMT_VERSION=%q\n' "$RUNTIME_DXMT_VERSION" > "$STATE_DIR/dxmt.env"
}

ensure_ori_bottle() {
  mkdir -p "$ORI_PREFIX"
  if prefix_is_initialized; then
    if [[ ! -f "$STATE_DIR/dxmt.env" ]]; then
      deploy_dxmt
    fi
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

  deploy_dxmt

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
