#!/usr/bin/env bash

# Runtime provider: frankea/Whisky's published WhiskyWine runtime.
# OriMac downloads the pinned runtime directly and stores it under its own
# Application Support directory. No Whisky GUI/app install is required.

WHISKY_RELEASE_BASE="https://github.com/frankea/Whisky/releases/download"

# Pinned upstream runtime metadata from frankea/Whisky.
RUNTIME_VERSION="3.1.1"
RUNTIME_SHA256="01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3"
RUNTIME_DXMT_VERSION="0.80"
RUNTIME_DXVK_VERSION="1.10.3"

ORI_RUNTIME_DIR="$APP_SUPPORT_DIR/runtime"
WHISKY_LIBRARIES="$ORI_RUNTIME_DIR/Libraries"
WHISKY_WINE="$WHISKY_LIBRARIES/Wine/bin/wine64"
WHISKY_WINESERVER="$WHISKY_LIBRARIES/Wine/bin/wineserver"

ORI_PREFIX="$APP_SUPPORT_DIR/prefix"
RUNTIME_STATE="$STATE_DIR/runtime.env"

plist_value() {
  local plist="$1" key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null
}

runtime_installed_version() {
  local plist="$WHISKY_LIBRARIES/WhiskyWineVersion.plist"
  [[ -f "$plist" ]] || return 1

  local major minor patch
  major="$(plist_value "$plist" 'version:major' || true)"
  minor="$(plist_value "$plist" 'version:minor' || true)"
  patch="$(plist_value "$plist" 'version:patch' || true)"
  [[ -n "$major" && -n "$minor" && -n "$patch" ]] || return 1
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

runtime_is_usable() {
  [[ -x "$WHISKY_WINE" ]] &&
  [[ -x "$WHISKY_WINESERVER" ]] &&
  [[ "$(runtime_installed_version 2>/dev/null || true)" == "$RUNTIME_VERSION" ]]
}

write_runtime_state() {
  printf 'RUNTIME_VERSION=%q\n' "$RUNTIME_VERSION" > "$RUNTIME_STATE"
  printf 'RUNTIME_SHA256=%q\n' "$RUNTIME_SHA256" >> "$RUNTIME_STATE"
  printf 'RUNTIME_DXMT_VERSION=%q\n' "$RUNTIME_DXMT_VERSION" >> "$RUNTIME_STATE"
  printf 'RUNTIME_DXVK_VERSION=%q\n' "$RUNTIME_DXVK_VERSION" >> "$RUNTIME_STATE"
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

install_runtime_headless() {
  local archive="$DOWNLOAD_DIR/Libraries-$RUNTIME_VERSION.tar.gz"
  local url="$WHISKY_RELEASE_BASE/v$RUNTIME_VERSION/Libraries.tar.gz"
  local stage="$APP_SUPPORT_DIR/.runtime-stage"

  if [[ ! -s "$archive" ]]; then
    info "Downloading WhiskyWine $RUNTIME_VERSION..."
    curl --fail --location --retry 3 --progress-bar "$url" -o "$archive.tmp"
    mv "$archive.tmp" "$archive"
  fi

  local actual expected
  actual="$(sha256_file "$archive" | tr '[:upper:]' '[:lower:]')"
  expected="$(printf '%s' "$RUNTIME_SHA256" | tr '[:upper:]' '[:lower:]')"
  if [[ "$actual" != "$expected" ]]; then
    rm -f "$archive"
    error "WhiskyWine checksum mismatch."
    error "Expected: $RUNTIME_SHA256"
    error "Actual:   $actual"
    exit 4
  fi

  info "Installing pinned Wine runtime..."
  rm -rf "$stage"
  mkdir -p "$stage"
  tar -xzf "$archive" -C "$stage"

  [[ -x "$stage/Libraries/Wine/bin/wine64" ]] || {
    rm -rf "$stage"
    error "Runtime archive is missing Libraries/Wine/bin/wine64."
    exit 4
  }

  rm -rf "$ORI_RUNTIME_DIR"
  mkdir -p "$ORI_RUNTIME_DIR"
  mv "$stage/Libraries" "$ORI_RUNTIME_DIR/Libraries"
  rm -rf "$stage"
  write_runtime_state

  runtime_is_usable || {
    error "Runtime installed but failed validation."
    exit 4
  }
}

ensure_runtime() {
  if runtime_is_usable; then
    return 0
  fi
  install_runtime_headless
}

wine_env() {
  export WINEPREFIX="$ORI_PREFIX"
  export WINEDEBUG="$(profile_value environment.WINEDEBUG)"
  export WINEESYNC="$(profile_value environment.WINEESYNC)"
  export WINEMSYNC="$(profile_value environment.WINEMSYNC)"
  export CX_ROOT="$WHISKY_LIBRARIES/Wine"
  export PATH="$WHISKY_LIBRARIES/Wine/bin:$PATH"

  if [[ -d "$WHISKY_LIBRARIES/DXMT" ]]; then
    export WINEDLLOVERRIDES="$(profile_value dllOverrides);${WINEDLLOVERRIDES:-}"
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
    # Re-deploy when the pinned runtime/backend version changes.
    local installed_dxmt=""
    if [[ -f "$STATE_DIR/dxmt.env" ]]; then
      # shellcheck disable=SC1090
      source "$STATE_DIR/dxmt.env"
      installed_dxmt="${DXMT_VERSION:-}"
    fi
    if [[ "$installed_dxmt" != "$RUNTIME_DXMT_VERSION" ]]; then
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

  # Keep the prefix in Windows 10 compatibility mode.
  wine_run reg add 'HKCU\\Software\\Wine' /v Version /d win10 /f >/dev/null 2>&1 || true

  printf 'PREFIX_VERSION=1\n' > "$STATE_DIR/prefix.env"
  info "Prefix ready: $ORI_PREFIX"
}

runtime_self_test() {
  info "Running Wine runtime self-test..."

  local version_output
  version_output="$(wine_run cmd /c ver 2>&1 || true)"
  if [[ -z "$version_output" ]]; then
    error "Wine command self-test produced no output."
    exit 7
  fi

  local system32="$ORI_PREFIX/drive_c/windows/system32"
  local dll
  for dll in d3d11.dll dxgi.dll d3d10core.dll winemetal.dll; do
    [[ -f "$system32/$dll" ]] || {
      error "DXMT self-test failed: $dll is not deployed."
      exit 7
    }
  done

  info "Wine responded successfully."
  info "DXMT $RUNTIME_DXMT_VERSION payload is deployed."
  info "Runtime self-test passed."
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
  rm -f "$STATE_DIR/prefix.env" "$STATE_DIR/dxmt.env"
  info "Prefix reset complete. Run ./ori to recreate it."
}
