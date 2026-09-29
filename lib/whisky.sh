#!/usr/bin/env bash

WHISKY_APP="/Applications/Whisky.app"
WHISKY_CLI="$WHISKY_APP/Contents/Resources/WhiskyCmd"
WHISKY_BREW_CASK="frankea/whisky/whisky"

ensure_homebrew() {
  if command_exists brew; then
    return 0
  fi

  warn "Homebrew is not installed. OriMac currently uses it to provision the Whisky runtime."
  if ! confirm "Install Homebrew now?"; then
    error "Homebrew is required for automatic runtime provisioning in this MVP."
    exit 3
  fi

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  if ! command_exists brew; then
    error "Homebrew installation finished but brew is not available in PATH."
    exit 3
  fi
}

ensure_runtime() {
  if [[ -x "$WHISKY_CLI" ]]; then
    return 0
  fi

  ensure_homebrew
  info "Installing Whisky runtime wrapper..."
  brew install --cask "$WHISKY_BREW_CASK"

  if [[ ! -x "$WHISKY_CLI" ]]; then
    error "Whisky installed, but embedded WhiskyCmd was not found at: $WHISKY_CLI"
    exit 4
  fi
}

whisky_cmd() {
  "$WHISKY_CLI" "$@"
}

bottle_exists() {
  whisky_cmd list 2>/dev/null | grep -Fq "$BOTTLE_NAME"
}

ensure_ori_bottle() {
  if bottle_exists; then
    return 0
  fi

  info "Creating dedicated Whisky bottle: $BOTTLE_NAME"
  whisky_cmd create "$BOTTLE_NAME"

  # Whisky currently performs final Wine-prefix bootstrap in the GUI.
  # Open it once so its runtime initializer can finish; later ./ori runs are CLI-only.
  info "Opening Whisky once to finish first-run runtime initialization."
  open -a Whisky
  warn "If Whisky shows a first-run setup screen, let it finish, then return here and press Enter."
  read -r

  if ! bottle_exists; then
    error "The OriMac bottle was not created correctly."
    exit 5
  fi
}

reset_bottle() {
  init_paths
  if ! [[ -x "$WHISKY_CLI" ]]; then
    warn "Whisky is not installed; there is no managed bottle to reset."
    return 0
  fi
  if ! bottle_exists; then
    info "No OriMac bottle exists. Nothing to reset."
    return 0
  fi
  if ! confirm "Delete the OriMac compatibility bottle? Steam/Ori data inside it will be removed."; then
    info "Reset cancelled."
    return 0
  fi
  whisky_cmd delete "$BOTTLE_NAME"
  info "Bottle reset complete. Run ./ori to recreate it."
}