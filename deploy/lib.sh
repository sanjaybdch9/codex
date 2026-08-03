#!/usr/bin/env bash
# Shared helpers + strict mode for the deploy scripts. Sourced, not run.
set -euo pipefail

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; BLU=$'\033[34m'; DIM=$'\033[2m'; RST=$'\033[0m'
else
  BOLD=; RED=; GRN=; YLW=; BLU=; DIM=; RST=
fi

log()  { printf '%s\n' "${BLU}==>${RST} ${BOLD}$*${RST}"; }
ok()   { printf '%s\n' "${GRN}✓${RST} $*"; }
warn() { printf '%s\n' "${YLW}!${RST} $*" >&2; }
die()  { printf '%s\n' "${RED}✗ $*${RST}" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 \
    || die "Required tool '$1' not found. Run  ./install-tools.sh  first (see deploy/README.md)."
}

# Resolve the directory this library lives in, and the project root above it.
DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DEPLOY_DIR/.." && pwd)"

load_config() { source "$DEPLOY_DIR/config.env"; }
