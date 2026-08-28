#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ $# -le 1 ]] || die "Uso: scripts/install-arch.sh [--dry-run]"

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

command -v pacman >/dev/null 2>&1 || die "Este instalador requiere pacman (Arch/CachyOS)"

if ! pacman -Si asterisk >/dev/null 2>&1; then
  die "El paquete 'asterisk' no está disponible en los repositorios configurados. En Arch/CachyOS no compilamos Asterisk a ciegas: seguí docs/ARCH-CACHYOS.md#asterisk-no-disponible para el fallback validado."
fi

packages=(docker docker-compose git curl openssl iproute2 ufw asterisk ca-certificates)
run pacman -S --needed --noconfirm "${packages[@]}"

if [[ "$DRY_RUN" == false ]]; then
  systemctl enable --now docker
  systemctl enable --now asterisk
  log_ok "Dependencias base instaladas en Arch/CachyOS"
else
  printf '+ systemctl enable --now docker\n'
  printf '+ systemctl enable --now asterisk\n'
fi
