#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT

"$ROOT/scripts/install.sh" --dry-run >"$out" 2>&1

grep -q 'FASE: preflight' "$out"
grep -q 'FASE: firewall' "$out"
grep -q 'FASE: dograh' "$out"
grep -q 'FASE: ollama' "$out"
grep -q 'FASE: final_verify' "$out"
grep -q 'Instalación terminada' "$out"

"$ROOT/scripts/configure-dograh.sh" --dry-run >/dev/null 2>&1

tmp_runtime="$(mktemp -d)"
RUNTIME_DIR="$tmp_runtime" "$ROOT/scripts/configure-firewall.sh" --dry-run >"$out" 2>&1
rm -rf "$tmp_runtime"
grep -q 'ufw' "$out"
grep -q 'DOGRAH_DOCKER_SUBNET' "$out"

if grep -Eq '\[\[ "\$DRY_RUN" == true \]\] && .*--dry-run.*\|\|' "$ROOT/scripts/install.sh"; then
  echo 'FAIL: install.sh contiene un fallback peligroso de dry-run a ejecución real' >&2
  exit 1
fi

echo 'PASS: dry-run es seguro y completa todas las fases sin requerir estado runtime'
