#!/usr/bin/env bash

STEAM_INSTALLER_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
STEAM_INSTALLER="$DOWNLOAD_DIR/SteamSetup.exe"
STEAM_DIR="$ORI_PREFIX/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_DIR/Steam.exe"
STEAM_APPS="$STEAM_DIR/steamapps"
ORI_MANIFEST="$STEAM_APPS/appmanifest_1057090.acf"

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
  [[ -f "$ORI_MANIFEST" ]] && grep -Eq '"appid"[[:space:]]+"1057090"' "$ORI_MANIFEST"
}

ori_install_dir() {
  local install_dir
  install_dir="$(awk -F'"' '/"installdir"/ {print $4; exit}' "$ORI_MANIFEST" 2>/dev/null || true)"
  [[ -n "$install_dir" ]] && printf '%s\n' "$STEAM_APPS/common/$install_dir"
}

launch_steam() {
  info "Opening Windows Steam..."
  wine_run "$STEAM_EXE" -silent
}

launch_ori() {
  info "Launching Ori and the Will of the Wisps..."
  # Steam URI launch preserves Steam DRM, cloud saves, achievements and overlay.
  wine_run "$STEAM_EXE" -silent -applaunch "$ORI_APP_ID"

  # Give Steam a short window to reject a malformed/missing launch.
  sleep 3
  info "Launch request handed to Steam."
}

doctor() {
  init_paths

  local macos arch rosetta runtime prefix steam ori disk
  macos="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  arch="$(uname -m)"
  rosetta="$(/usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1 && echo available || echo missing)"
  runtime="$(runtime_is_usable && echo ready || echo missing)"
  prefix="$(prefix_is_initialized && echo ready || echo missing)"
  steam="$(steam_is_installed && echo installed || echo missing)"
  ori="$(ori_is_installed && echo installed || echo missing)"
  disk="$(df -h "$HOME" | awk 'NR==2 {print $4}')"

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
