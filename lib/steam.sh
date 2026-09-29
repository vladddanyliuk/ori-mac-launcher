#!/usr/bin/env bash

STEAM_INSTALLER_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
STEAM_INSTALLER="$DOWNLOAD_DIR/SteamSetup.exe"
STEAM_EXE='C:\Program Files (x86)\Steam\Steam.exe'

download_steam() {
  if [[ -s "$STEAM_INSTALLER" ]]; then
    return 0
  fi
  info "Downloading official Windows Steam installer..."
  curl --fail --location --retry 3 --output "$STEAM_INSTALLER.tmp" "$STEAM_INSTALLER_URL"
  mv "$STEAM_INSTALLER.tmp" "$STEAM_INSTALLER"
}

ori_games_json() {
  whisky_cmd games "$BOTTLE_NAME" --json
}

ensure_steam() {
  if ori_games_json >/dev/null 2>&1; then
    return 0
  fi

  download_steam
  info "Installing Windows Steam into the OriMac bottle..."
  whisky_cmd run "$BOTTLE_NAME" "$STEAM_INSTALLER"
  info "Steam installer launched. Complete the normal Steam sign-in if prompted."
}

ori_is_installed() {
  ori_games_json 2>/dev/null | grep -Eq '"appId"[[:space:]]*:[[:space:]]*"?1057090"?'
}

launch_steam() {
  info "Opening Windows Steam..."
  whisky_cmd run "$BOTTLE_NAME" "$STEAM_EXE"
}

launch_ori() {
  info "Launching Ori and the Will of the Wisps..."
  whisky_cmd launch "$ORI_APP_ID" --bottle "$BOTTLE_NAME"
}

doctor() {
  init_paths
  printf 'OriMac diagnostics\n'
  printf '==================\n'
  printf 'macOS: %s\n' "$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  printf 'Architecture: %s\n' "$(uname -m)"
  printf 'Rosetta: %s\n' "$(/usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1 && echo available || echo missing)"
  printf 'Homebrew: %s\n' "$(command -v brew 2>/dev/null || echo missing)"
  printf 'Whisky app: %s\n' "$([[ -d "$WHISKY_APP" ]] && echo installed || echo missing)"
  printf 'Whisky CLI: %s\n' "$([[ -x "$WHISKY_CLI" ]] && echo available || echo missing)"
  if [[ -x "$WHISKY_CLI" ]]; then
    printf 'Ori bottle: %s\n' "$(bottle_exists && echo present || echo missing)"
    if bottle_exists; then
      printf 'Ori installed: %s\n' "$(ori_is_installed && echo yes || echo no)"
    else
      printf 'Ori installed: unknown (bottle missing)\n'
    fi
  else
    printf 'Ori bottle: unknown (runtime missing)\n'
    printf 'Ori installed: unknown (runtime missing)\n'
  fi
  printf 'App support: %s\n' "$APP_SUPPORT_DIR"
  printf 'Logs: %s\n' "$LOG_DIR"
  printf 'Disk free: %s\n' "$(df -h "$HOME" | awk 'NR==2 {print $4}')"
}