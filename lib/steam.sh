#!/usr/bin/env bash

STEAM_INSTALLER_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
STEAM_INSTALLER="$DOWNLOAD_DIR/SteamSetup.exe"
STEAM_DIR="$ORI_PREFIX/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_DIR/Steam.exe"
STEAM_APPS="$STEAM_DIR/steamapps"
ORI_MANIFEST="$STEAM_APPS/appmanifest_${ORI_APP_ID}.acf"
STEAM_LOGIN_USERS="$STEAM_DIR/config/loginusers.vdf"

download_steam() {
  if [[ -s "$STEAM_INSTALLER" ]]; then
    return 0
  fi

  info "Downloading official Windows Steam installer..."
  curl --fail --location --retry 3 --progress-bar     "$STEAM_INSTALLER_URL" -o "$STEAM_INSTALLER.tmp"
  mv "$STEAM_INSTALLER.tmp" "$STEAM_INSTALLER"
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
  wine_run "$STEAM_INSTALLER" /S
  wineserver_wait

  if ! steam_is_installed; then
    warn "Silent Steam installation did not finish synchronously; retrying interactively."
    wine_run "$STEAM_INSTALLER"
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
  wine_run "$STEAM_EXE" -silent
}

ori_process_running() {
  local tasks
  tasks="$(wine_run tasklist 2>/dev/null || true)"
  printf '%s\n' "$tasks" | grep -Eiq '(^|[[:space:]])'"$ORI_EXE"'([[:space:]]|$)'
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
    warn "Steam is installed, but no signed-in account is detected."
    info "Opening Steam so you can sign in. Re-run ./ori afterwards."
    launch_steam
    return 8
  fi

  info "Launching Ori and the Will of the Wisps..."
  wine_run "$STEAM_EXE" -silent -applaunch "$ORI_APP_ID"

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

  local macos arch rosetta runtime prefix steam ori disk last_launch
  macos="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  arch="$(uname -m)"
  rosetta="$(/usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1 && echo available || echo missing)"
  runtime="$(runtime_is_usable && echo ready || echo missing)"
  prefix="$(prefix_is_initialized && echo ready || echo missing)"
  steam="$(steam_is_installed && echo installed || echo missing)"
  ori="$(ori_is_installed && echo installed || echo missing)"
  disk="$(df -h "$HOME" | awk 'NR==2 {print $4}')"
  last_launch="never"
  if [[ -f "$STATE_DIR/last-launch.env" ]]; then
    last_launch="$(tr '\n' ' ' < "$STATE_DIR/last-launch.env")"
  fi

  cat <<EOF
OriMac diagnostics
==================
macOS:          $macos
Architecture:   $arch
Rosetta:        $rosetta
Runtime:        $runtime
Pinned version: $RUNTIME_VERSION
Renderer:       DXMT $RUNTIME_DXMT_VERSION
Runtime wine:   $WHISKY_WINE
Prefix:         $prefix
Steam:          $steam
Ori 1057090:    $ori
App support:    $APP_SUPPORT_DIR
Logs:           $LOG_DIR
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
