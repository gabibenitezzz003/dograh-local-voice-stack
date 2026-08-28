#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Caso 1: una instalación existente con IDs que el proyecto pretende administrar
# debe abortar antes de modificar archivos.
existing="$TMP/existing"
mkdir -p "$existing"
cat > "$existing/pjsip.conf" <<'CFG'
[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:5060

[2001]
type=endpoint
context=from-internal
CFG
printf '[general]\nenabled=yes\n' > "$existing/http.conf"
printf '[general]\n' > "$existing/ari.conf"
printf '[from-internal]\nexten => 600,1,Echo()\n' > "$existing/extensions.conf"
printf '' > "$existing/websocket_client.conf"

before="$(sha256sum "$existing"/* | sort)"
set +e
conflict_output="$(ASTERISK_DIR="$existing" RUNTIME_DIR="$TMP/runtime-conflict" \
  ARI_PASSWORD=testari SIP_PASSWORD=testsip \
  bash "$ROOT/scripts/configure-asterisk.sh" --render-only "$existing" 2>&1)"
conflict_rc=$?
set -e

[[ $conflict_rc -ne 0 ]] || {
  printf 'FAIL: configure-asterisk aceptó IDs PJSIP existentes fuera del bloque administrado\n' >&2
  exit 1
}
grep -Fq 'Conflicto de configuración existente' <<<"$conflict_output" || {
  printf 'FAIL: no explicó el conflicto de configuración existente\n%s\n' "$conflict_output" >&2
  exit 1
}
after="$(sha256sum "$existing"/* | sort)"
[[ "$before" == "$after" ]] || {
  printf 'FAIL: configure-asterisk modificó archivos pese al conflicto\n' >&2
  diff -u <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
  exit 1
}

# Caso 2: si una validación runtime falla después de escribir, la transacción
# debe restaurar el estado anterior automáticamente.
rollback="$TMP/rollback"
fakebin="$TMP/fakebin"
mkdir -p "$rollback" "$fakebin"
for f in http.conf ari.conf pjsip.conf extensions.conf websocket_client.conf; do
  printf '; original %s\n' "$f" > "$rollback/$f"
done
rollback_before="$(sha256sum "$rollback"/* | sort)"

cat > "$fakebin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
exit 0
EOF_SYSTEMCTL
cat > "$fakebin/asterisk" <<'EOF_ASTERISK'
#!/usr/bin/env bash
cmd="${*: -1}"
case "$cmd" in
  'module show like '*) printf '%s\n' "${cmd#module show like }" ;;
  'pjsip show transports') printf 'Transport: transport-tcp tcp 0 0 0.0.0.0:5060\n' ;;
  *) printf 'OK\n' ;;
esac
EOF_ASTERISK
chmod +x "$fakebin/systemctl" "$fakebin/asterisk"

set +e
rollback_output="$(PATH="$fakebin:/usr/bin:/bin" ASTERISK_DIR="$rollback" \
  RUNTIME_DIR="$TMP/runtime-rollback" ARI_PASSWORD=testari SIP_PASSWORD=testsip \
  bash "$ROOT/scripts/configure-asterisk.sh" 2>&1)"
rollback_rc=$?
set -e

[[ $rollback_rc -ne 0 ]] || {
  printf 'FAIL: se esperaba fallo de validación runtime simulado\n' >&2
  exit 1
}
grep -Fq 'Rollback de Asterisk completado' <<<"$rollback_output" || {
  printf 'FAIL: no informó rollback automático\n%s\n' "$rollback_output" >&2
  exit 1
}
rollback_after="$(sha256sum "$rollback"/* | sort)"
[[ "$rollback_before" == "$rollback_after" ]] || {
  printf 'FAIL: rollback no restauró exactamente los archivos originales\n' >&2
  diff -u <(printf '%s\n' "$rollback_before") <(printf '%s\n' "$rollback_after") >&2 || true
  exit 1
}

printf 'PASS: Asterisk aborta conflictos antes de escribir y revierte fallos runtime\n'
