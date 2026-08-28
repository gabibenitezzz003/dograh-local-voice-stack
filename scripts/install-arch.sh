#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
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

base_packages=(docker docker-compose git curl openssl iproute2 ufw ca-certificates base-devel)
run pacman -S --needed --noconfirm "${base_packages[@]}"

install_asterisk_from_aur() {
  local build_user build_dir
  build_user="${SUDO_USER:-}"
  build_dir="/tmp/dograh-local-voice-stack-asterisk"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "Asterisk no está en los repositorios configurados; se usará el paquete AUR 'asterisk'."
    printf '+ git clone https://aur.archlinux.org/asterisk.git %q\n' "$build_dir"
    printf '+ cd %q && makepkg -s --noconfirm --clean\n' "$build_dir"
    printf '+ pacman -U --noconfirm <paquete-generado-por-makepkg>\n'
    return 0
  fi

  [[ -n "$build_user" && "$build_user" != root ]] || die "Para compilar Asterisk desde AUR ejecutá el instalador con sudo desde un usuario normal (ej.: sudo ./scripts/install.sh). makepkg no debe ejecutarse como root."

  log_warn "Asterisk no está en los repositorios configurados. Se compilará el paquete AUR comunitario 'asterisk' como usuario $build_user."
  log_warn "AUR es comunitario/no oficial. El PKGBUILD usado será https://aur.archlinux.org/asterisk.git"

  rm -rf "$build_dir"
  install -d -m 0755 -o "$build_user" -g "$(id -gn "$build_user")" "$build_dir"
  sudo -u "$build_user" git clone --depth 1 https://aur.archlinux.org/asterisk.git "$build_dir"
  sudo -u "$build_user" bash -lc "cd '$build_dir' && makepkg -s --noconfirm --clean"

  mapfile -t package_files < <(sudo -u "$build_user" bash -lc "cd '$build_dir' && makepkg --packagelist")
  (( ${#package_files[@]} > 0 )) || die "makepkg terminó sin informar paquetes instalables de Asterisk"
  pacman -U --needed --noconfirm "${package_files[@]}"
}

if command -v asterisk >/dev/null 2>&1; then
  log_ok "Asterisk ya está instalado; no se reinstala"
elif pacman -Si asterisk >/dev/null 2>&1; then
  run pacman -S --needed --noconfirm asterisk
else
  install_asterisk_from_aur
fi

if [[ "$DRY_RUN" == false ]]; then
  systemctl enable --now docker
  systemctl enable --now asterisk
  log_ok "Dependencias base instaladas en Arch/CachyOS"
else
  printf '+ systemctl enable --now docker\n'
  printf '+ systemctl enable --now asterisk\n'
fi
