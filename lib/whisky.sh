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
PREFIX_SCHEMA_VERSION="1"
TUNING_SCHEMA_VERSION="9"

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
  WINEPREFIX="$ORI_PREFIX"
  WINEDEBUG="$(profile_value environment.WINEDEBUG)"
  WINEESYNC="$(profile_value environment.WINEESYNC)"
  WINEMSYNC="$(profile_value environment.WINEMSYNC)"
  LC_ALL="$(profile_value environment.LC_ALL)"
  LANG="$(profile_value environment.LANG)"
  LC_TIME="$(profile_value environment.LC_TIME)"
  LC_NUMERIC="$(profile_value environment.LC_NUMERIC)"
  CEF_DISABLE_SANDBOX="$(profile_value environment.CEF_DISABLE_SANDBOX)"
  STEAM_DISABLE_CEF_SANDBOX="$(profile_value environment.STEAM_DISABLE_CEF_SANDBOX)"
  STEAM_RUNTIME="$(profile_value environment.STEAM_RUNTIME)"
  WINHTTP_CONNECT_TIMEOUT="$(profile_value environment.WINHTTP_CONNECT_TIMEOUT)"
  WINHTTP_RECEIVE_TIMEOUT="$(profile_value environment.WINHTTP_RECEIVE_TIMEOUT)"
  WINE_FORCE_HTTP11="$(profile_value environment.WINE_FORCE_HTTP11)"
  WINE_MAX_CONNECTIONS_PER_SERVER="$(profile_value environment.WINE_MAX_CONNECTIONS_PER_SERVER)"
  MVK_CONFIG_LOG_LEVEL="$(profile_value environment.MVK_CONFIG_LOG_LEVEL)"
  D3DM_VALIDATION="$(profile_value environment.D3DM_VALIDATION)"
  MTL_DEBUG_LAYER="$(profile_value environment.MTL_DEBUG_LAYER)"
  MTL_ENABLE_METAL_EVENTS="$(profile_value environment.MTL_ENABLE_METAL_EVENTS)"
  MONO_THREADS_SUSPEND="$(profile_value environment.MONO_THREADS_SUSPEND)"
  WINE_LARGE_ADDRESS_AWARE="$(profile_value environment.WINE_LARGE_ADDRESS_AWARE)"
  D3DM_FORCE_D3D11="$(profile_value environment.D3DM_FORCE_D3D11)"
  WINE_DISABLE_NTDLL_THREAD_REGS="$(profile_value environment.WINE_DISABLE_NTDLL_THREAD_REGS)"
  WINEPRELOADRESERVE="$(profile_value environment.WINEPRELOADRESERVE)"
  CX_ROOT="$WHISKY_LIBRARIES/Wine"
  PATH="$WHISKY_LIBRARIES/Wine/bin:$PATH"
  export WINEPREFIX WINEDEBUG WINEESYNC
  if [[ "$WINEMSYNC" == "1" ]]; then
    export WINEMSYNC
  else
    unset WINEMSYNC
  fi
  export LC_ALL LANG LC_TIME LC_NUMERIC
  export CEF_DISABLE_SANDBOX STEAM_DISABLE_CEF_SANDBOX STEAM_RUNTIME
  export WINHTTP_CONNECT_TIMEOUT WINHTTP_RECEIVE_TIMEOUT WINE_FORCE_HTTP11
  export WINE_MAX_CONNECTIONS_PER_SERVER
  export MVK_CONFIG_LOG_LEVEL D3DM_VALIDATION MTL_DEBUG_LAYER MTL_ENABLE_METAL_EVENTS
  export MONO_THREADS_SUSPEND WINE_LARGE_ADDRESS_AWARE D3DM_FORCE_D3D11
  export WINE_DISABLE_NTDLL_THREAD_REGS WINEPRELOADRESERVE
  export CX_ROOT PATH

  # Deliberately keep DLL load-order overrides out of the process
  # environment. Steam spawns Chromium helpers, and WINEDLLOVERRIDES would be
  # inherited by all of them. Per-program AppDefaults are synced separately.
  unset WINEDLLOVERRIDES
}

wine_run() {
  wine_env
  "$WHISKY_WINE" "$@"
}

wine_program() {
  local executable="$1"
  shift
  wine_env
  "$WHISKY_WINE" start /unix "$executable" "$@"
}

wine_program_wait() {
  local executable="$1"
  shift
  wine_env
  "$WHISKY_WINE" start /wait /unix "$executable" "$@"
}

wineserver_wait() {
  wine_env
  "$WHISKY_WINESERVER" -w
}

prefix_is_initialized() {
  [[ -f "$ORI_PREFIX/system.reg" ]] &&
  [[ -d "$ORI_PREFIX/drive_c/windows/system32" ]]
}

prefix_state_version() {
  local state="$STATE_DIR/prefix.env"
  [[ -f "$state" ]] || return 1
  awk -F= '/^PREFIX_VERSION=/ {print $2; exit}' "$state"
}

validate_prefix_schema() {
  if ! prefix_is_initialized; then
    return 0
  fi

  local existing
  existing="$(prefix_state_version 2>/dev/null || true)"

  # A prefix created before schema tracking is compatible with schema v1 and can
  # be adopted without deleting Steam/game data.
  if [[ -z "$existing" ]]; then
    printf 'PREFIX_VERSION=%s\n' "$PREFIX_SCHEMA_VERSION" > "$STATE_DIR/prefix.env"
    return 0
  fi

  if [[ "$existing" != "$PREFIX_SCHEMA_VERSION" ]]; then
    error "Prefix schema $existing is incompatible with launcher schema $PREFIX_SCHEMA_VERSION."
    error "Run ./ori --reset to rebuild the isolated Ori prefix."
    exit 5
  fi
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

is_wine_builtin_pe() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local marker
  marker="$(LC_ALL=C dd if="$file" bs=1 skip=64 count=16 2>/dev/null || true)"
  [[ "$marker" == "Wine builtin DLL" ]]
}

remove_native_dll_if_present() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if ! is_wine_builtin_pe "$file"; then
    rm -f "$file"
  fi
}

deploy_dxvk() {
  local payload="$WHISKY_LIBRARIES/DXVK"
  local system32="$ORI_PREFIX/drive_c/windows/system32"
  local syswow64="$ORI_PREFIX/drive_c/windows/syswow64"
  local dll

  [[ -d "$payload/x64" ]] || {
    error "Pinned runtime is missing the DXVK x64 payload."
    exit 5
  }

  # Remove DXMT's native dxgi before enabling DXVK. The maintained Whisky
  # runtime intentionally uses Wine's builtin DXGI with DXVK.
  remove_native_dll_if_present "$system32/dxgi.dll"
  [[ -d "$syswow64" ]] && remove_native_dll_if_present "$syswow64/dxgi.dll"

  for dll in "$payload/x64"/*.dll; do
    [[ -f "$dll" ]] || continue
    cp -f "$dll" "$system32/$(basename "$dll")"
  done

  if [[ -d "$syswow64" && -d "$payload/x32" ]]; then
    for dll in "$payload/x32"/*.dll; do
      [[ -f "$dll" ]] || continue
      cp -f "$dll" "$syswow64/$(basename "$dll")"
    done
  fi
}

clear_dll_override_scope() {
  local exe="$1"
  wine_run reg delete "HKCU\\Software\\Wine\\AppDefaults\\$exe\\DllOverrides" /f >/dev/null 2>&1 || true
}

sync_program_dll_overrides() {
  local game_key="HKCU\\Software\\Wine\\AppDefaults\\$ORI_EXE\\DllOverrides"
  local clause name mode

  # The bottle itself has no graphics override. This keeps Steam and all of its
  # helper processes on Wine's default/builtin graphics stack.
  wine_run reg delete 'HKCU\\Software\\Wine\\DllOverrides' /f >/dev/null 2>&1 || true

  # Prune stale program scopes from earlier launcher revisions.
  clear_dll_override_scope "steam.exe"
  clear_dll_override_scope "steamwebhelper.exe"
  clear_dll_override_scope "$ORI_EXE"

  IFS=';' read -r -a clauses <<< "$(profile_value dllOverrides)"
  for clause in "${clauses[@]}"; do
    name="${clause%%=*}"
    mode="${clause#*=}"
    [[ -n "$name" ]] || continue
    wine_run reg add "$game_key" /v "$name" /t REG_SZ /d "$mode" /f >/dev/null
  done
}

apply_graphics_backend() {
  local backend current=""
  backend="$(profile_value preferredRenderer)"

  if [[ -f "$STATE_DIR/backend.env" ]]; then
    current="$(awk -F= '/^BACKEND=/ {print $2; exit}' "$STATE_DIR/backend.env" 2>/dev/null || true)"
  fi

  case "$backend" in
    DXMT)
      # Remove a stale DXVK d3d9 native DLL; DXMT does not use it.
      remove_native_dll_if_present "$ORI_PREFIX/drive_c/windows/system32/d3d9.dll"
      [[ -d "$ORI_PREFIX/drive_c/windows/syswow64" ]] &&         remove_native_dll_if_present "$ORI_PREFIX/drive_c/windows/syswow64/d3d9.dll"
      deploy_dxmt
      ;;
    DXVK)
      deploy_dxvk
      ;;
    *)
      error "Unsupported graphics backend in profile: $backend"
      exit 5
      ;;
  esac

  printf 'BACKEND=%s\n' "$backend" > "$STATE_DIR/backend.env"

  if [[ "$current" != "$backend" ]]; then
    info "Graphics backend switched to $backend."
  fi
}

ensure_ori_bottle() {
  mkdir -p "$ORI_PREFIX"
  validate_prefix_schema

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

  # Keep the prefix in Windows 10 compatibility mode without opening winecfg UI.
  wine_run winecfg -v win10 >/dev/null 2>&1

  printf 'PREFIX_VERSION=%s\n' "$PREFIX_SCHEMA_VERSION" > "$STATE_DIR/prefix.env"
  info "Prefix ready: $ORI_PREFIX"
}

detect_main_display_pixels() {
  /usr/sbin/system_profiler SPDisplaysDataType -json 2>/dev/null | /usr/bin/python3 -c '
import json, re, sys
try:
    data=json.load(sys.stdin).get("SPDisplaysDataType", [])
    displays=[]
    for gpu in data:
        displays.extend(gpu.get("spdisplays_ndrvs", []) or [])
    main=next((d for d in displays if d.get("spdisplays_main")=="spdisplays_yes"), displays[0] if displays else {})
    raw=main.get("_spdisplays_pixels") or main.get("_spdisplays_resolution") or main.get("spdisplays_resolution") or ""
    m=re.search(r"(\d+)\s*x\s*(\d+)", raw)
    if m:
        print(f"{m.group(1)}x{m.group(2)}")
except Exception:
    pass
'
}

apply_display_tuning() {
  local target_width target_height
  target_width="$(profile_value display.targetWidth)"
  target_height="$(profile_value display.targetHeight)"

  wine_run reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /t REG_SZ /d "$(profile_value display.retinaMode)" /f >/dev/null

  local dpi_aware app_name
  dpi_aware="$(profile_value highDpiAware 2>/dev/null || echo 0)"
  app_name="$(printf '%s' "$ORI_EXE" | tr '[:upper:]' '[:lower:]')"
  if [[ "$dpi_aware" == "1" ]]; then
    wine_run reg add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' \
      /v "$app_name" /t REG_SZ /d HIGHDPIAWARE /f >/dev/null
  else
    wine_run reg delete 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' \
      /v "$app_name" /f >/dev/null 2>&1 || true
  fi
  wine_run reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d "$(profile_value display.dpi)" /f >/dev/null
  wine_run reg add 'HKCU\Software\Wine\Direct3D' /v VideoMemorySize /t REG_SZ /d "$(profile_value display.videoMemoryMB)" /f >/dev/null

  # Avoid Wine's virtual desktop: it can make a native game look like a streamed/scaled surface.
  wine_run reg delete 'HKCU\Software\Wine\Explorer' /v Desktop /f >/dev/null 2>&1 || true

  local uses_registry game_key width_key height_key fullscreen_key native_key monitor_key
  uses_registry="$(profile_value screenmanagerRegistry 2>/dev/null || echo 0)"
  if [[ "$uses_registry" == "1" ]]; then
    game_key="$(profile_value registryKey)"
    width_key="$(profile_value screenWidthRegistryName 2>/dev/null || true)"
    height_key="$(profile_value screenHeightRegistryName 2>/dev/null || true)"
    fullscreen_key="$(profile_value fullscreenRegistryName 2>/dev/null || true)"
    native_key="$(profile_value useNativeRegistryName 2>/dev/null || true)"
    monitor_key="$(profile_value monitorRegistryName 2>/dev/null || true)"

    [[ -n "$width_key" ]] && wine_run reg add "$game_key" /v "$width_key" /t REG_DWORD /d "$target_width" /f >/dev/null
    [[ -n "$height_key" ]] && wine_run reg add "$game_key" /v "$height_key" /t REG_DWORD /d "$target_height" /f >/dev/null
    [[ -n "$fullscreen_key" ]] && wine_run reg add "$game_key" /v "$fullscreen_key" /t REG_DWORD /d "$(profile_value display.fullscreenMode)" /f >/dev/null
    [[ -n "$native_key" ]] && wine_run reg add "$game_key" /v "$native_key" /t REG_DWORD /d "$(profile_value display.useNativeResolution)" /f >/dev/null
    [[ -n "$monitor_key" ]] && wine_run reg add "$game_key" /v "$monitor_key" /t REG_DWORD /d 0 /f >/dev/null
  fi
}

apply_audio_tuning() {
  wine_run reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d "$(profile_value audio.driver)" /f >/dev/null
  wine_run reg add 'HKCU\Software\Wine\DirectSound' /v HelBuflen /t REG_SZ /d "$(profile_value audio.directSoundBuffer)" /f >/dev/null
}

apply_game_tuning() {
  local state="$STATE_DIR/tuning.env"
  local applied=""
  if [[ -f "$state" ]]; then
    applied="$(awk -F= '/^TUNING_VERSION=/ {print $2; exit}' "$state" 2>/dev/null || true)"
  fi

  # Reapply on every launch because Unity may rewrite its Screenmanager keys.
  apply_graphics_backend
  sync_program_dll_overrides
  apply_display_tuning
  apply_audio_tuning

  printf 'TUNING_VERSION=%s\n' "$TUNING_SCHEMA_VERSION" > "$state"
  printf 'GAME_SLUG=%q\n' "$GAME_SLUG" >> "$state"
  printf 'DISPLAY_PIXELS=%q\n' "$(detect_main_display_pixels || true)" >> "$state"
  printf 'TARGET_RESOLUTION=%qx%q\n' "$(profile_value display.targetWidth)" "$(profile_value display.targetHeight)" >> "$state"
  printf 'BACKEND=%q\n' "$(profile_value preferredRenderer)" >> "$state"
  printf 'RETINA_MODE=%q\n' "$(profile_value display.retinaMode)" >> "$state"
  printf 'HIGH_DPI_AWARE=%q\n' "$(profile_value highDpiAware 2>/dev/null || echo 0)" >> "$state"
  printf 'DPI=%q\n' "$(profile_value display.dpi)" >> "$state"
  printf 'VIDEO_MEMORY_MB=%q\n' "$(profile_value display.videoMemoryMB)" >> "$state"
  printf 'AUDIO_DRIVER=%q\n' "$(profile_value audio.driver)" >> "$state"
  printf 'AUDIO_BUFFER=%q\n' "$(profile_value audio.directSoundBuffer)" >> "$state"
  printf 'ESYNC=%q\n' "$(profile_value environment.WINEESYNC)" >> "$state"
  printf 'MSYNC=%q\n' "$(profile_value environment.WINEMSYNC)" >> "$state"

  if [[ "$applied" != "$TUNING_SCHEMA_VERSION" ]]; then
    info "Resetting cached Wine audio devices for the new tuning profile..."
    wine_run reg delete 'HKLM\Software\Microsoft\Windows\CurrentVersion\MMDevices' /f >/dev/null 2>&1 || true

    local sync_label="ESYNC"
    [[ "$(profile_value environment.WINEMSYNC)" == "1" ]] && sync_label="MSYNC (with ESYNC)"
    info "Applied $GAME_NAME profile: $(profile_value display.targetWidth)x$(profile_value display.targetHeight) fullscreen + CoreAudio stable buffer + $sync_label."
    wine_env
    "$WHISKY_WINESERVER" -k >/dev/null 2>&1 || true
    "$WHISKY_WINESERVER" -w >/dev/null 2>&1 || true
  fi
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
  local backend
  backend="$(profile_value preferredRenderer)"

  case "$backend" in
    DXMT)
      for dll in d3d11.dll dxgi.dll d3d10core.dll winemetal.dll; do
        [[ -f "$system32/$dll" ]] || {
          error "DXMT self-test failed: $dll is not deployed."
          exit 7
        }
      done
      ;;
    DXVK)
      for dll in d3d11.dll d3d10core.dll; do
        [[ -f "$system32/$dll" ]] || {
          error "DXVK self-test failed: $dll is not deployed."
          exit 7
        }
      done
      ;;
  esac

  info "Wine responded successfully."
  info "$backend backend payload is deployed."
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
