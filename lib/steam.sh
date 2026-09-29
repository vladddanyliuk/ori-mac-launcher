#!/usr/bin/env bash

STEAM_INSTALLER_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
STEAM_INSTALLER="$DOWNLOAD_DIR/SteamSetup.exe"
STEAM_DIR="$ORI_PREFIX/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_DIR/Steam.exe"
STEAM_APPS="$STEAM_DIR/steamapps"
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

manifest_for_appid() {
  local appid="$1"
  local name="appmanifest_${appid}.acf"
  local candidate="$STEAM_APPS/$name"

  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$(find "$ORI_PREFIX/drive_c" -type f -name "$name" -print -quit 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

profile_slug_from_request() {
  case "${1:-}" in
    blind|first|261570) printf '%s\n' "blind" ;;
    blind-de|de|definitive|387290) printf '%s\n' "blind-de" ;;
    wotw|wisps|1057090) printf '%s\n' "wotw" ;;
    "") return 1 ;;
    *) return 2 ;;
  esac
}

select_installed_game() {
  local quiet="${1:-0}"

  if manifest_for_appid 261570 >/dev/null 2>&1; then
    load_game_profile "blind"
  elif manifest_for_appid 387290 >/dev/null 2>&1; then
    load_game_profile "blind-de"
  elif manifest_for_appid 1057090 >/dev/null 2>&1; then
    load_game_profile "wotw"
  else
    return 1
  fi

  [[ "$quiet" == "1" ]] || info "Detected installed game: $GAME_NAME (Steam $ORI_APP_ID)."
}

select_game_for_run() {
  local requested="${1:-}"
  local slug=""

  if [[ -n "$requested" ]]; then
    slug="$(profile_slug_from_request "$requested" || true)"
    if [[ -z "$slug" ]]; then
      error "Unknown Ori game selector: $requested"
      error "Use: blind, blind-de, or wotw."
      return 64
    fi
    load_game_profile "$slug"
    info "Selected game: $GAME_NAME (Steam $ORI_APP_ID)."
    return 0
  fi

  if select_installed_game 0; then
    return 0
  fi

  # Fresh setup with no Ori installation: preserve the original project target.
  load_game_profile "wotw"
  info "No installed Ori title detected; defaulting to $GAME_NAME."
}

ori_manifest_path() {
  manifest_for_appid "$ORI_APP_ID"
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
  info "Opening install dialog for $GAME_NAME..."
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
    error "$GAME_NAME installation was not detected within 4 hours."
    return 10
  fi

  info "$GAME_NAME installation detected."
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
  local uses_registry
  uses_registry="$(profile_value screenmanagerRegistry 2>/dev/null || echo 0)"

  if [[ "$uses_registry" != "1" ]]; then
    info "Display mode is forced by Unity launch arguments for $GAME_NAME."
    return 0
  fi

  local game_key width_key height_key fullscreen_key native_key width height fullscreen native
  game_key="$(profile_value registryKey)"
  width_key="$(profile_value screenWidthRegistryName 2>/dev/null || true)"
  height_key="$(profile_value screenHeightRegistryName 2>/dev/null || true)"
  fullscreen_key="$(profile_value fullscreenRegistryName 2>/dev/null || true)"
  native_key="$(profile_value useNativeRegistryName 2>/dev/null || true)"

  [[ -n "$width_key" ]] && width="$(wine_run reg query "$game_key" /v "$width_key" 2>/dev/null | awk '/REG_DWORD/ {print $NF; exit}' || true)"
  [[ -n "$height_key" ]] && height="$(wine_run reg query "$game_key" /v "$height_key" 2>/dev/null | awk '/REG_DWORD/ {print $NF; exit}' || true)"
  [[ -n "$fullscreen_key" ]] && fullscreen="$(wine_run reg query "$game_key" /v "$fullscreen_key" 2>/dev/null | awk '/REG_DWORD/ {print $NF; exit}' || true)"
  [[ -n "$native_key" ]] && native="$(wine_run reg query "$game_key" /v "$native_key" 2>/dev/null | awk '/REG_DWORD/ {print $NF; exit}' || true)"

  info "Display registry after launch: width=${width:-unknown} height=${height:-unknown} fullscreen=${fullscreen:-unknown} useNative=${native:-n/a}"
}

launch_ori() {
  if ! steam_has_login; then
    printf 'LAST_LAUNCH_STATUS=steam-sign-in-required\n' > "$STATE_DIR/last-launch.env"
    printf 'LAST_LAUNCH_AT=%q\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$STATE_DIR/last-launch.env"
    warn "Steam is installed, but no signed-in account is detected."
    launch_steam
    return 8
  fi

  local target_width target_height
  target_width="$(profile_value display.targetWidth)"
  target_height="$(profile_value display.targetHeight)"

  info "Launching $GAME_NAME at ${target_width}x${target_height}..."
  wine_program "$STEAM_EXE" -silent -applaunch "$ORI_APP_ID" \
    -force-d3d11 \
    -screen-width "$target_width" \
    -screen-height "$target_height" \
    -screen-fullscreen 1

  if wait_for_ori_process; then
    printf 'LAST_LAUNCH_STATUS=started\n' > "$STATE_DIR/last-launch.env"
    printf 'LAST_LAUNCH_GAME=%q\n' "$GAME_SLUG" >> "$STATE_DIR/last-launch.env"
    printf 'LAST_LAUNCH_AT=%q\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$STATE_DIR/last-launch.env"
    info "Game process detected: $ORI_EXE"
    sleep 4
    log_effective_ori_display
    return 0
  fi

  printf 'LAST_LAUNCH_STATUS=not-detected\n' > "$STATE_DIR/last-launch.env"
  printf 'LAST_LAUNCH_GAME=%q\n' "$GAME_SLUG" >> "$STATE_DIR/last-launch.env"
  printf 'LAST_LAUNCH_AT=%q\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$STATE_DIR/last-launch.env"
  error "Steam received the launch request, but $ORI_EXE was not detected within 60 seconds."
  error "Diagnostics: ./ori --doctor"
  return 9
}

installed_ori_summary() {
  local out=""
  manifest_for_appid 261570 >/dev/null 2>&1 && out="${out}Blind Forest (261570), "
  manifest_for_appid 387290 >/dev/null 2>&1 && out="${out}Blind Forest DE (387290), "
  manifest_for_appid 1057090 >/dev/null 2>&1 && out="${out}Will of the Wisps (1057090), "
  out="${out%, }"
  [[ -n "$out" ]] && printf '%s\n' "$out" || printf '%s\n' "none"
}

game_log_path() {
  local install_dir users_dir
  install_dir="$(ori_install_dir 2>/dev/null || true)"
  users_dir="$ORI_PREFIX/drive_c/users"

  /usr/bin/python3 - "$install_dir" "$users_dir" <<'PY'
import os
import sys

roots=[p for p in sys.argv[1:] if p and os.path.isdir(p)]
names={"output_log.txt","player.log"}
matches=[]

for root in roots:
    for base, dirs, files in os.walk(root):
        # Avoid crawling Steam browser/cache trees that can be huge and irrelevant.
        dirs[:] = [d for d in dirs if d.lower() not in {
            "htmlcache","shadercache","cef_cache","cache","logs"
        }]
        for name in files:
            if name.lower() in names:
                path=os.path.join(base,name)
                try:
                    matches.append((os.path.getmtime(path), path))
                except OSError:
                    pass

if matches:
    matches.sort(reverse=True)
    print(matches[0][1])
PY
}

show_game_logs() {
  local requested="${1:-}"
  if [[ -n "$requested" ]]; then
    select_game_for_run "$requested" || return $?
  else
    select_installed_game 1 || {
      error "No installed Ori game was detected."
      return 1
    }
  fi

  local log_path
  log_path="$(game_log_path 2>/dev/null || true)"

  if [[ -z "$log_path" || ! -f "$log_path" ]]; then
    error "No Unity game log was found for $GAME_NAME."
    error "Expected an output_log.txt or Player.log under the game folder or Wine user AppData."
    error "Launcher log is still available at: $CURRENT_LOG"
    return 1
  fi

  info "Game log: $log_path"
  printf '\n===== last 250 lines: %s =====\n' "$GAME_NAME"
  tail -n 250 "$log_path"
  printf '\n===== end game log =====\n'
}


doctor() {
  init_paths

  if steam_is_installed; then
    select_installed_game 1 || true
  fi

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
  [[ -f "$STATE_DIR/tuning.env" ]] && tuning="$(tr '\n' ' ' < "$STATE_DIR/tuning.env")"
  last_launch="never"
  [[ -f "$STATE_DIR/last-launch.env" ]] && last_launch="$(tr '\n' ' ' < "$STATE_DIR/last-launch.env")"

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
Detected games: $(installed_ori_summary)
Selected game:  $GAME_NAME (Steam $ORI_APP_ID)
Game target:    $(profile_value display.targetWidth)x$(profile_value display.targetHeight), fullscreen
Retina/DPI:     $(profile_value display.retinaMode) / $(profile_value display.dpi)
Sync:           ESYNC=$(profile_value environment.WINEESYNC), MSYNC=$(profile_value environment.WINEMSYNC)
Audio:          $(profile_value audio.driver), buffer $(profile_value audio.directSoundBuffer)
Runtime wine:   $WHISKY_WINE
Prefix:         $prefix
Steam:          $steam
Steam login:    $steam_login
Selected game installed: $ori
App support:    $APP_SUPPORT_DIR
Logs:           $LOG_DIR
App writable:   $app_writable
Logs writable:  $logs_writable
Disk free:      $disk
Tuning state:   $tuning
Last launch:    $last_launch
EOF

  local manifest_path exe_path
  manifest_path="$(ori_manifest_path 2>/dev/null || true)"
  exe_path="$(ori_executable_path 2>/dev/null || true)"
  [[ -n "$manifest_path" ]] && printf 'Game manifest:   %s\n' "$manifest_path"
  [[ -n "$exe_path" ]] && printf 'Game executable: %s\n' "$exe_path"
}
