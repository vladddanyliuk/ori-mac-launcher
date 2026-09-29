#!/usr/bin/env bash

STEAM_INSTALLER_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
STEAM_INSTALLER="$DOWNLOAD_DIR/SteamSetup.exe"
STEAM_DIR="$ORI_PREFIX/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_DIR/Steam.exe"
STEAM_APPS="$STEAM_DIR/steamapps"
ORI_MANIFEST_NAME="appmanifest_${ORI_APP_ID}.acf"
STEAM_LOGIN_USERS="$STEAM_DIR/config/loginusers.vdf"

steam_installer_is_sane() {
  [[ -s "$STEAM_INSTALLER" ]] || return 1
  local magic
  magic="$(LC_ALL=C dd if="$STEAM_INSTALLER" bs=1 count=2 2>/dev/null || true)"
  [[ "$magic" == "MZ" ]]
}

download_steam() {
  if steam_installer_is_sane; then
    return 0
  fi

  rm -f "$STEAM_INSTALLER" "$STEAM_INSTALLER.tmp"
  info "Downloading official Windows Steam installer..."
  curl --fail --location --retry 3 --progress-bar \
    "$STEAM_INSTALLER_URL" -o "$STEAM_INSTALLER.tmp"
  mv "$STEAM_INSTALLER.tmp" "$STEAM_INSTALLER"

  if ! steam_installer_is_sane; then
    rm -f "$STEAM_INSTALLER"
    error "Steam download did not look like a valid Windows executable."
    exit 6
  fi
}

steam_is_installed() {
  [[ -f "$STEAM_EXE" ]]
}

ensure_steam() {
  if steam_is_installed; then
    return 0
  fi

  download_steam
  info "Installing Windows Steam..."
  # /S is the NSIS silent-install flag used by SteamSetup.
  wine_program_wait "$STEAM_INSTALLER" /S

  if ! steam_is_installed; then
    warn "Silent Steam installation did not finish synchronously; retrying interactively."
    wine_program_wait "$STEAM_INSTALLER"
  fi

  steam_is_installed || {
    error "Steam installation failed. Run ./ori --doctor for diagnostics."
    exit 6
  }
}

ori_manifest_path() {
  local candidate

  candidate="$STEAM_APPS/$ORI_MANIFEST_NAME"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  # Steam can place a library elsewhere inside the isolated C: drive.
  candidate="$(find "$ORI_PREFIX/drive_c" -type f -name "$ORI_MANIFEST_NAME" -print -quit 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

ori_is_installed() {
  local manifest
  manifest="$(ori_manifest_path 2>/dev/null || true)"
  [[ -n "$manifest" && -f "$manifest" ]] || return 1
  grep -Eq "\"appid\"[[:space:]]+\"${ORI_APP_ID}\"" "$manifest"
}

ori_install_dir() {
  local manifest install_dir steamapps_dir
  manifest="$(ori_manifest_path 2>/dev/null || true)"
  [[ -n "$manifest" && -f "$manifest" ]] || return 1

  install_dir="$(awk -F'"' '/"installdir"/ {print $4; exit}' "$manifest" 2>/dev/null || true)"
  [[ -n "$install_dir" ]] || return 1

  steamapps_dir="$(dirname "$manifest")"
  printf '%s\n' "$steamapps_dir/common/$install_dir"
}

ori_executable_path() {
  local dir
  dir="$(ori_install_dir 2>/dev/null || true)"
  [[ -n "$dir" && -d "$dir" ]] || return 1

  find "$dir" -type f -iname "$ORI_EXE" -print -quit 2>/dev/null
}

steam_has_login() {
  [[ -s "$STEAM_LOGIN_USERS" ]] && grep -Fq '"AccountName"' "$STEAM_LOGIN_USERS"
}

launch_steam() {
  info "Opening Windows Steam..."
  # Do not use -silent here: first-run/login/install flows need the actual Steam UI.
  wine_program "$STEAM_EXE"
}

wait_for_steam_login() {
  local timeout_seconds="${1:-900}"
  local elapsed=0
  while [[ "$elapsed" -lt "$timeout_seconds" ]]; do
    if steam_has_login; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

open_ori_install_dialog() {
  info "Opening Ori install dialog in Steam..."
  wine_run start "steam://install/$ORI_APP_ID"
}

wait_for_ori_install() {
  local timeout_seconds="${1:-14400}"
  local elapsed=0
  while [[ "$elapsed" -lt "$timeout_seconds" ]]; do
    if ori_is_installed; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  return 1
}

ensure_ori_installed_interactive() {
  if ori_is_installed; then
    return 0
  fi

  launch_steam

  if ! steam_has_login; then
    info "Sign in to Windows Steam. OriMac is waiting for the login to complete..."
    if ! wait_for_steam_login 900; then
      error "Steam login was not detected within 15 minutes."
      return 8
    fi
    info "Steam login detected."
  fi

  open_ori_install_dialog
  info "Choose the install location in Steam if asked. OriMac will wait for the download to finish."

  if ! wait_for_ori_install 14400; then
    error "Ori installation was not detected within 4 hours."
    return 10
  fi

  info "Ori installation detected."
}

ori_process_running() {
  local tasks
  tasks="$(wine_run tasklist 2>/dev/null || true)"
  if [[ -z "$tasks" ]]; then
    tasks="$(wine_run winedbg --command "info proc" 2>/dev/null || true)"
  fi
  printf '%s\n' "$tasks" | grep -Fqi "$ORI_EXE"
}

wait_for_ori_process() {
  local attempts=30
  local i=0
  while [[ "$i" -lt "$attempts" ]]; do
    if ori_process_running; then
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  return 1
}

log_effective_ori_display() {
  local game_key='HKCU\Software\Moon Studios\OriAndTheWilloftheWisps'
  local width height fullscreen native

  width="$(wine_run reg query "$game_key" /v 'Screenmanager Resolution Width_h182942802' 2>/dev/null | awk '/REG_DWORD/ {print $NF; exit}' || true)"
  height="$(wine_run reg query "$game_key" /v 'Screenmanager Resolution Height_h2627697771' 2>/dev/null | awk '/REG_DWORD/ {print $NF; exit}' || true)"
  fullscreen="$(wine_run reg query "$game_key" /v 'Screenmanager Fullscreen mode_h3630240806' 2>/dev/null | awk '/REG_DWORD/ {print $NF; exit}' || true)"
  native="$(wine_run reg query "$game_key" /v 'Screenmanager Resolution Use Native_h1405027254' 2>/dev/null | awk '/REG_DWORD/ {print $NF; exit}' || true)"

  info "Ori display registry after launch: width=${width:-unknown} height=${height:-unknown} fullscreen=${fullscreen:-unknown} useNative=${native:-unknown}"
}

launch_ori() {
  if ! steam_has_login; then
    printf 'LAST_LAUNCH_STATUS=steam-sign-in-required\n' > "$STATE_DIR/last-launch.env"
    printf 'LAST_LAUNCH_AT=%q\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$STATE_DIR/last-launch.env"
    warn "Steam is installed, but no signed-in account is detected."
    info "Opening Steam so you can sign in. Re-run ./ori afterwards."
    launch_steam
    return 8
  fi

  local target_width target_height
  target_width="$(profile_value display.targetWidth)"
  target_height="$(profile_value display.targetHeight)"

  info "Launching Ori and the Will of the Wisps at ${target_width}x${target_height}..."
  # Ori uses Unity 2018.4. Force the standalone-player mode every launch so
  # game-side settings cannot silently fall back to the macOS logical resolution.
  wine_program "$STEAM_EXE" -silent -applaunch "$ORI_APP_ID" \
    -force-d3d11 \
    -screen-width "$target_width" \
    -screen-height "$target_height" \
    -screen-fullscreen 1

  if wait_for_ori_process; then
    printf 'LAST_LAUNCH_STATUS=started\n' > "$STATE_DIR/last-launch.env"
    printf 'LAST_LAUNCH_AT=%q\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$STATE_DIR/last-launch.env"
    info "Ori process detected: $ORI_EXE"
    sleep 4
    log_effective_ori_display
    return 0
  fi

  printf 'LAST_LAUNCH_STATUS=not-detected\n' > "$STATE_DIR/last-launch.env"
  printf 'LAST_LAUNCH_AT=%q\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$STATE_DIR/last-launch.env"
  error "Steam received the launch request, but $ORI_EXE was not detected within 60 seconds."
  error "Check Steam for a sign-in, update, first-run dialog, or game error."
  error "Diagnostics: ./ori --doctor"
  return 9
}

doctor() {
  init_paths

  local macos model memory_gb display_pixels arch rosetta runtime prefix steam steam_login ori disk last_launch app_writable logs_writable tuning
  macos="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  model="$(sysctl -n hw.model 2>/dev/null || echo unknown)"
  memory_gb="$(awk -v b="$(sysctl -n hw.memsize 2>/dev/null || echo 0)" 'BEGIN {printf "%.0f", b/1073741824}')"
  display_pixels="$(detect_main_display_pixels 2>/dev/null || true)"
  [[ -n "$display_pixels" ]] || display_pixels="unknown"
  arch="$(uname -m)"
  rosetta="$(/usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1 && echo available || echo missing)"
  runtime="$(runtime_is_usable && echo ready || echo missing)"
  prefix="$(prefix_is_initialized && echo ready || echo missing)"
  steam="$(steam_is_installed && echo installed || echo missing)"
  steam_login="$(steam_has_login && echo detected || echo not-detected)"
  ori="$(ori_is_installed && echo installed || echo missing)"
  disk="$(df -h "$HOME" | awk 'NR==2 {print $4}')"
  app_writable="$([[ -w "$APP_SUPPORT_DIR" ]] && echo yes || echo no)"
  logs_writable="$([[ -w "$LOG_DIR" ]] && echo yes || echo no)"
  tuning="not-applied"
  if [[ -f "$STATE_DIR/tuning.env" ]]; then
    tuning="$(tr '\n' ' ' < "$STATE_DIR/tuning.env")"
  fi
  last_launch="never"
  if [[ -f "$STATE_DIR/last-launch.env" ]]; then
    last_launch="$(tr '\n' ' ' < "$STATE_DIR/last-launch.env")"
  fi

  cat <<EOF
OriMac diagnostics
==================
macOS:          $macos
Mac model:      $model
Memory:         ${memory_gb} GB
Display pixels: $display_pixels
Architecture:   $arch
Rosetta:        $rosetta
Runtime:        $runtime
Pinned version: $RUNTIME_VERSION
Renderer:       DXMT $RUNTIME_DXMT_VERSION
Game target:    $(profile_value display.targetWidth)x$(profile_value display.targetHeight), exclusive
Retina/DPI:     $(profile_value display.retinaMode) / $(profile_value display.dpi)
Sync:           ESYNC=$(profile_value environment.WINEESYNC), MSYNC=$(profile_value environment.WINEMSYNC)
Audio:          $(profile_value audio.driver), buffer $(profile_value audio.directSoundBuffer)
Runtime wine:   $WHISKY_WINE
Prefix:         $prefix
Steam:          $steam
Steam login:    $steam_login
Ori $ORI_APP_ID:    $ori
App support:    $APP_SUPPORT_DIR
Logs:           $LOG_DIR
App writable:   $app_writable
Logs writable:  $logs_writable
Disk free:      $disk
Tuning state:   $tuning
Last launch:    $last_launch
EOF

  if [[ -f "$WHISKY_LIBRARIES/WhiskyWineVersion.plist" ]]; then
    printf 'Runtime version: %s\n' "$(runtime_installed_version 2>/dev/null || echo unknown)"
    printf 'DXMT version:    %s\n' "$(plist_value "$WHISKY_LIBRARIES/WhiskyWineVersion.plist" dxmtVersion || echo unknown)"
    printf 'DXVK version:    %s\n' "$(plist_value "$WHISKY_LIBRARIES/WhiskyWineVersion.plist" dxvkVersion || echo unknown)"
  fi

  local manifest_path exe_path
  manifest_path="$(ori_manifest_path 2>/dev/null || true)"
  exe_path="$(ori_executable_path 2>/dev/null || true)"
  [[ -n "$manifest_path" ]] && printf 'Ori manifest:    %s\n' "$manifest_path"
  [[ -n "$exe_path" ]] && printf 'Ori executable:  %s\n' "$exe_path"
}
