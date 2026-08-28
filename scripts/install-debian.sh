#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ $# -le 1 ]] || die "Uso: scripts/install-debian.sh [--dry-run]"

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

command -v apt-get >/dev/null 2>&1 || die "Este instalador requiere apt-get (Ubuntu/Debian)"

run apt-get update
compose_pkg=docker-compose-v2
if [[ "$DRY_RUN" == false ]] && ! apt-cache show docker-compose-v2 >/dev/null 2>&1; then
  if apt-cache show docker-compose-plugin >/dev/null 2>&1; then
    compose_pkg=docker-compose-plugin
  elif apt-cache show docker-compose >/dev/null 2>&1; then
    compose_pkg=docker-compose
  else
    die "No encontré Docker Compose v2/plugin en APT. Instalalo desde Docker y reintentá."
  fi
fi

packages=(docker.io "$compose_pkg" asterisk ufw curl openssl iproute2 ca-certificates git)
if [[ "$DRY_RUN" == true ]]; then
  printf '+ DEBIAN_FRONTEND=noninteractive apt-get install -y'
  printf ' %q' "${packages[@]}"
  printf '\n'
  printf '+ systemctl enable --now docker\n'
  printf '+ systemctl enable --now asterisk\n'
else
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
  systemctl enable --now docker
  systemctl enable --now asterisk
  log_ok "Dependencias base instaladas en Ubuntu/Debian"
fi
