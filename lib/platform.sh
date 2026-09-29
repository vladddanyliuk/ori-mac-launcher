#!/usr/bin/env bash

platform_check() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    error "OriMac supports macOS only."
    exit 2
  fi

  local arch
  arch="$(uname -m)"
  if [[ "$arch" != "arm64" ]]; then
    error "MVP currently targets Apple Silicon Macs (arm64). Detected: $arch"
    exit 2
  fi

  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  if [[ "$major" -lt 15 ]]; then
    error "macOS Sequoia 15 or newer is required."
    exit 2
  fi

  if ! /usr/bin/pgrep oahd >/dev/null 2>&1 && ! /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    warn "Rosetta 2 is required by the current runtime."
    info "macOS will ask for administrator approval to install Rosetta."
    if [[ "$EUID" -eq 0 ]]; then
      /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    else
      sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    fi
  fi
}