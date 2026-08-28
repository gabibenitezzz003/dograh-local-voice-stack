#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo '== Sintaxis Bash =='
while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find scripts tests -type f -name '*.sh' -print0)

echo 'PASS: sintaxis Bash'

echo '== Contrato estático =='
bash tests/test-configs.sh

echo '== Seguridad Asterisk =='
bash tests/test-asterisk-safety.sh

echo '== Dry-run general =='
bash tests/dry-run-test.sh

echo '== Fallback Arch/AUR aislado =='
bash tests/test-install-arch-dry-run.sh

echo 'PASS: suite estática completa'
