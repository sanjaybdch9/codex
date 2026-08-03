#!/usr/bin/env bash
# Installs the command-line tools needed to deploy (macOS).
# Handles Runbook Part 3. May prompt for your Mac password (that's normal).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Checking for Homebrew…"
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew (it may ask for your Mac password)…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew usable in this session (Apple Silicon path).
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
else
  ok "Homebrew already installed."
fi

log "Installing AWS CLI, eksctl, kubectl…"
brew install awscli eksctl kubectl

log "Installing Docker Desktop…"
if brew install --cask docker; then
  ok "Docker Desktop installed."
else
  warn "Docker Desktop install needs approval or is already present. If it failed, install it manually from docker.com."
fi

echo
ok "Tools installed."
echo
warn "Two manual steps remain before you can deploy:"
echo "  1. OPEN Docker Desktop once (Applications folder) and wait for the whale icon in the menu bar."
echo "  2. Run  aws configure  and paste your Access Key ID + Secret (Runbook Part 4)."
echo
echo "Then run:  ./deploy.sh"
