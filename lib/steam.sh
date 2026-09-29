#!/usr/bin/env bash

STEAM_INSTALLER_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
STEAM_INSTALLER="$DOWNLOAD_DIR/SteamSetup.exe"
STEAM_DIR="$ORI_PREFIX/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_DIR/Steam.exe"
STEAM_APPS="$STEAM_DIR/steamapps"
ORI_MANIFEST="$STEAM_APPS/appmanifest_${ORI_APP_ID}.acf"
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
  wineserver_wait

  if ! steam_is_installed; then
    warn "Silent Steam installation did not finish synchronously; retrying interactively."
    wine_program_wait "$STEAM_INSTALLER"
    wineserver_wait
  fi

  steam_is_installed || {
    error "Steam installation failed. Run ./ori --doctor for diagnostics."
    exit 6
  }
}

ori_is_installed() {
  [[ -f "$ORI_MANIFEST" ]] && grep -Eq '"appid"[[:space:]]+"'${ORI_APP_ID}'"' "$ORI_MANIFEST"
}

ori_install_dir() {
  local install_dir
  install_dir="$(awk -F'"' '/"installdir"/ {print $4; exit}' "$ORI_MANIFEST" 2>/dev/null || true)"
  [[ -n "$install_dir" ]] && printf '%s\n' "$STEAM_APPS/common/$install_dir"
}

steam_has_login() {
  [[ -s "$STEAM_LOGIN_USERS" ]] && grep -Fq '"AccountName"' "$STEAM_LOGIN_USERS"
}

launch_steam() {
  info "Opening Windows Steam..."
  wine_program "$STEAM_EXE" -silent
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

launch_ori() {
  if ! steam_has_login; then
    printf 'LAST_LAUNCH_STATUS=steam-sign-in-required\n' > "$STATE_DIR/last-launch.env"
    printf 'LAST_LAUNCH_AT=%q\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$STATE_DIR/last-launch.env"
    warn "Steam is installed, but no signed-in account is detected."
    info "Opening Steam so you can sign in. Re-run ./ori afterwards."
    launch_steam
    return 8
  fi

  info "Launching Ori and the Will of the Wisps..."
  wine_program "$STEAM_EXE" -silent -applaunch "$ORI_APP_ID"

  if wait_for_ori_process; then
    printf 'LAST_LAUNCH_STATUS=started\n' > "$STATE_DIR/last-launch.env"
    printf 'LAST_LAUNCH_AT=%q\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$STATE_DIR/last-launch.env"
    info "Ori process detected: $ORI_EXE"
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

  local macos model arch rosetta runtime prefix steam steam_login ori disk last_launch app_writable logs_writable
  macos="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  model="$(sysctl -n hw.model 2>/dev/null || echo unknown)"
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
  last_launch="never"
  if [[ -f "$STATE_DIR/last-launch.env" ]]; then
    last_launch="$(tr '\n' ' ' < "$STATE_DIR/last-launch.env")"
  fi

  cat <<EOF
OriMac diagnostics
==================
macOS:          $macos
Mac model:      $model
Architecture:   $arch
Rosetta:        $rosetta
Runtime:        $runtime
Pinned version: $RUNTIME_VERSION
Renderer:       DXMT $RUNTIME_DXMT_VERSION
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
Last launch:    $last_launch
EOF

  if [[ -f "$WHISKY_LIBRARIES/WhiskyWineVersion.plist" ]]; then
    printf 'Runtime version: %s\n' "$(runtime_installed_version 2>/dev/null || echo unknown)"
    printf 'DXMT version:    %s\n' "$(plist_value "$WHISKY_LIBRARIES/WhiskyWineVersion.plist" dxmtVersion || echo unknown)"
    printf 'DXVK version:    %s\n' "$(plist_value "$WHISKY_LIBRARIES/WhiskyWineVersion.plist" dxvkVersion || echo unknown)"
  fi

  if [[ -f "$ORI_MANIFEST" ]]; then
    printf 'Ori path:        %s\n' "$(ori_install_dir)"
  fi
}
