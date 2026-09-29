#!/usr/bin/env bash

APP_NAME="OriMac"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/${APP_NAME}"
STATE_DIR="$APP_SUPPORT_DIR/state"
DOWNLOAD_DIR="$APP_SUPPORT_DIR/downloads"
CONFIG_DIR="$APP_SUPPORT_DIR/config"
LOG_DIR="${HOME}/Library/Logs/${APP_NAME}"
CURRENT_LOG="$LOG_DIR/ori.log"
BOTTLE_NAME="OriMac"
ORI_APP_ID="1057090"

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
  local code="$1" line="$2"
  error "Command failed at line $line (exit $code)."
  error "Log: $CURRENT_LOG"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

confirm() {
  local prompt="${1:-Continue?}"
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}