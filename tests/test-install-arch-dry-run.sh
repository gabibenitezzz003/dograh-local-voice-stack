#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/pacman" <<'PACMAN'
#!/usr/bin/env bash
if [[ "${1:-}" == "-Si" && "${2:-}" == "asterisk" ]]; then
  exit 1
fi
printf 'fake pacman %s\n' "$*"
PACMAN
chmod +x "$TMP/bin/pacman"

ln -s /usr/bin/dirname "$TMP/bin/dirname"

output="$(PATH="$TMP/bin" /usr/bin/bash "$ROOT/scripts/install-arch.sh" --dry-run 2>&1)" || {
  printf 'FAIL: install-arch --dry-run abortó cuando Asterisk no estaba en repositorios\n%s\n' "$output" >&2
  exit 1
}

grep -Fq 'aur.archlinux.org/asterisk.git' <<<"$output" || {
  printf 'FAIL: dry-run no mostró el fallback AUR de Asterisk\n%s\n' "$output" >&2
  exit 1
}

grep -Fq 'pacman -S --needed --noconfirm' <<<"$output" || {
  printf 'FAIL: dry-run no mostró la instalación base con pacman\n%s\n' "$output" >&2
  exit 1
}

printf 'PASS: install-arch --dry-run continúa y muestra fallback AUR cuando Asterisk no está en repositorios\n'
