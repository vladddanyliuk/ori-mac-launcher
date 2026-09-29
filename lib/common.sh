#!/usr/bin/env bash

APP_NAME="OriMac"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/${APP_NAME}"
STATE_DIR="$APP_SUPPORT_DIR/state"
DOWNLOAD_DIR="$APP_SUPPORT_DIR/downloads"
CONFIG_DIR="$APP_SUPPORT_DIR/config"
LOG_DIR="${HOME}/Library/Logs/${APP_NAME}"
CURRENT_LOG="$LOG_DIR/ori.log"

GAME_PROFILE=""
GAME_SLUG=""
GAME_NAME=""
ORI_APP_ID=""
ORI_EXE=""

profile_value() {
  local key="$1"
  /usr/bin/plutil -extract "$key" raw -o - "$GAME_PROFILE" 2>/dev/null
}

load_game_profile() {
  local slug="$1"
  local profile="$ROOT_DIR/config/$slug.plist"

  if [[ ! -r "$profile" ]] || ! /usr/bin/plutil -lint "$profile" >/dev/null 2>&1; then
    printf 'OriMac: invalid or missing game profile: %s\n' "$profile" >&2
    exit 70
  fi

  GAME_PROFILE="$profile"
  GAME_SLUG="$slug"
  GAME_NAME="$(profile_value name)" || exit 70
  ORI_APP_ID="$(profile_value steamAppId)" || exit 70
  ORI_EXE="$(profile_value executable)" || exit 70

  if [[ -z "$GAME_NAME" || -z "$ORI_APP_ID" || -z "$ORI_EXE" ]]; then
    printf 'OriMac: game profile %s is missing required fields.\n' "$profile" >&2
    exit 70
  fi
}

# Default remains Will of the Wisps until Steam installation detection chooses
# an already-installed Ori title.
load_game_profile "wotw"

init_paths() {
  mkdir -p "$STATE_DIR" "$DOWNLOAD_DIR" "$CONFIG_DIR" "$LOG_DIR"
}

rotate_logs() {
  mkdir -p "$LOG_DIR"
  if [[ -f "$CURRENT_LOG" ]] && [[ $(wc -c < "$CURRENT_LOG") -gt 2097152 ]]; then
    mv -f "$CURRENT_LOG" "$LOG_DIR/ori.log.1"
  fi
}

_ts() { date '+%Y-%m-%d %H:%M:%S'; }
info() { printf '[%s] [INFO] %s\n' "$(_ts)" "$*"; }
warn() { printf '[%s] [WARN] %s\n' "$(_ts)" "$*" >&2; }
error() { printf '[%s] [ERROR] %s\n' "$(_ts)" "$*" >&2; }

on_error() {
  local code="$1" line="$2" command="${3:-unknown}"
  case "$command" in
    "$HOME"*) command="~${command#"$HOME"}" ;;
  esac
  error "Command failed at line $line (exit $code): $command"
  error "Log: $CURRENT_LOG"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

confirm() {
  local prompt="${1:-Continue?}"
  local answer=""
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}
