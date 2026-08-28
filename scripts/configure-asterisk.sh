#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"

BEGIN_MARKER='; BEGIN DOGRAH-LOCAL-VOICE-STACK'
END_MARKER='; END DOGRAH-LOCAL-VOICE-STACK'
ASTERISK_DIR="${ASTERISK_DIR:-/etc/asterisk}"
RENDER_ONLY=false

usage() {
  cat <<'USAGE'
Uso: scripts/configure-asterisk.sh [--render-only DIRECTORIO]

Sin opciones: configura /etc/asterisk, preservando contenido ajeno mediante
un bloque administrado por el proyecto.

--render-only DIR  renderiza los cinco archivos en DIR sin tocar Asterisk ni systemd.
USAGE
}

if [[ "${1:-}" == "--render-only" ]]; then
  [[ -n "${2:-}" ]] || die "--render-only requiere un directorio"
  RENDER_ONLY=true
  ASTERISK_DIR="$2"
  shift 2
fi
[[ $# -eq 0 ]] || { usage; exit 2; }

load_project_env
: "${SIP_EXTENSION:=2001}"
: "${ECHO_EXTENSION:=600}"
: "${SIP_PORT:=5060}"
: "${ARI_PORT:=8088}"
: "${DOGRAH_API_PORT:=8000}"

ensure_secrets() {
  ensure_runtime_dirs
  local secrets="$RUNTIME_DIR/secrets.env"
  if [[ -f "$secrets" ]]; then
    # shellcheck disable=SC1090
    source "$secrets"
  fi
  if [[ -z "${ARI_PASSWORD:-}" ]]; then
    require_cmd openssl
    ARI_PASSWORD="$(openssl rand -hex 24)"
    write_env_value "$secrets" ARI_PASSWORD "$ARI_PASSWORD"
  fi
  if [[ -z "${SIP_PASSWORD:-}" ]]; then
    require_cmd openssl
    SIP_PASSWORD="$(openssl rand -hex 12)"
    write_env_value "$secrets" SIP_PASSWORD "$SIP_PASSWORD"
  fi
  export ARI_PASSWORD SIP_PASSWORD
}

render_template() {
  local template="$1" content
  content="$(cat "$template")"
  content="${content//\{\{SIP_EXTENSION\}\}/$SIP_EXTENSION}"
  content="${content//\{\{ECHO_EXTENSION\}\}/$ECHO_EXTENSION}"
  content="${content//\{\{SIP_PORT\}\}/$SIP_PORT}"
  content="${content//\{\{ARI_PORT\}\}/$ARI_PORT}"
  content="${content//\{\{DOGRAH_API_PORT\}\}/$DOGRAH_API_PORT}"
  content="${content//\{\{ARI_PASSWORD\}\}/$ARI_PASSWORD}"
  content="${content//\{\{SIP_PASSWORD\}\}/$SIP_PASSWORD}"
  printf '%s\n' "$content"
}

strip_managed_block() {
  local source="$1"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$source"
}

managed_block() {
  local source="$1"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin {take=1; next}
    $0 == end {take=0; exit}
    take {print}
  ' "$source" 2>/dev/null || true
}

outside_managed_content() {
  local source="$1"
  [[ -f "$source" ]] || return 0
  strip_managed_block "$source"
}

assert_no_existing_conflicts() {
  local conflicts=() content section

  content="$(outside_managed_content "$ASTERISK_DIR/pjsip.conf")"
  for section in transport-udp transport-tcp "$SIP_EXTENSION" "$SIP_EXTENSION-auth"; do
    if grep -Fxq "[$section]" <<<"$content"; then
      conflicts+=("pjsip.conf:[$section]")
    fi
  done

  content="$(outside_managed_content "$ASTERISK_DIR/ari.conf")"
  grep -Fxq '[dograh]' <<<"$content" && conflicts+=("ari.conf:[dograh]")

  content="$(outside_managed_content "$ASTERISK_DIR/websocket_client.conf")"
  grep -Fxq '[dograh]' <<<"$content" && conflicts+=("websocket_client.conf:[dograh]")

  content="$(outside_managed_content "$ASTERISK_DIR/extensions.conf")"
  if grep -Eq "^[[:space:]]*exten[[:space:]]*=>[[:space:]]*${ECHO_EXTENSION}," <<<"$content"; then
    conflicts+=("extensions.conf:${ECHO_EXTENSION}")
  fi

  if (( ${#conflicts[@]} > 0 )); then
    die "Conflicto de configuración existente: ${conflicts[*]}. El instalador no modificó Asterisk. Esta instalación ya usa IDs que el proyecto administra; usá una VM/máquina limpia o migrá esos IDs antes de una instalación real."
  fi
}

CONFIG_FILES=(http.conf ari.conf pjsip.conf extensions.conf websocket_client.conf)
TXN_DIR=""
TXN_ACTIVE=false

begin_transaction() {
  ensure_runtime_dirs
  TXN_DIR="$RUNTIME_DIR/backups/transaction-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$TXN_DIR"
  chmod 700 "$TXN_DIR"
  local name source
  for name in "${CONFIG_FILES[@]}"; do
    source="$ASTERISK_DIR/$name"
    if [[ -e "$source" ]]; then
      cp -a "$source" "$TXN_DIR/$name"
    else
      : > "$TXN_DIR/$name.absent"
    fi
  done
  TXN_ACTIVE=true
}

rollback_transaction() {
  [[ "$TXN_ACTIVE" == true ]] || return 0
  local name target
  set +e
  for name in "${CONFIG_FILES[@]}"; do
    target="$ASTERISK_DIR/$name"
    if [[ -f "$TXN_DIR/$name.absent" ]]; then
      rm -f "$target"
    elif [[ -e "$TXN_DIR/$name" ]]; then
      cp -a "$TXN_DIR/$name" "$target"
    fi
  done
  if command -v systemctl >/dev/null 2>&1 && command -v asterisk >/dev/null 2>&1; then
    systemctl restart asterisk >/dev/null 2>&1 || true
  fi
  TXN_ACTIVE=false
  log_ok "Rollback de Asterisk completado; se restauró el estado anterior"
  set -e
}

on_exit() {
  local status=$?
  if (( status != 0 )) && [[ "$TXN_ACTIVE" == true ]]; then
    rollback_transaction
  fi
  exit "$status"
}
trap on_exit EXIT

ensure_general_section() {
  local target="$1"
  if [[ ! -s "$target" ]] || ! grep -Eq '^\[general\]' "$target"; then
    printf '[general]\n' >> "$target"
  fi
}

apply_block() {
  local target="$1" rendered="$2" needs_general="${3:-false}"
  mkdir -p "$(dirname "$target")"
  touch "$target"
  if [[ "$needs_general" == true ]]; then
    ensure_general_section "$target"
  fi
  local tmp
  tmp="$(mktemp)"
  strip_managed_block "$target" > "$tmp"
  while [[ -s "$tmp" ]] && [[ -z "$(tail -n1 "$tmp")" ]]; do sed -i '$d' "$tmp"; done
  [[ -s "$tmp" ]] && printf '\n' >> "$tmp"
  printf '%s\n%s\n%s\n' "$BEGIN_MARKER" "$rendered" "$END_MARKER" >> "$tmp"
  if cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    return 1
  fi
  if [[ "$RENDER_ONLY" == false ]]; then
    backup_file "$target"
  fi
  cat "$tmp" > "$target"
  rm -f "$tmp"
  return 0
}

transport_signature() {
  awk -v ext="[$SIP_EXTENSION]" '
    $0 == "[transport-udp]" {take=1}
    take && $0 == ext {exit}
    take {print}
  '
}

validate_modules() {
  local modules=(res_ari.so chan_websocket.so res_http_websocket.so res_pjsip_transport_websocket.so res_websocket_client.so)
  local module output
  for module in "${modules[@]}"; do
    output="$(asterisk -rx "module show like $module" 2>/dev/null || true)"
    grep -q "$module" <<<"$output" || die "Asterisk no tiene cargado $module. Revisá docs/ASTERISK.md"
  done
}

restart_or_recover() {
  if systemctl restart asterisk; then
    return 0
  fi
  log_warn "systemctl restart asterisk devolvió error; verificando recuperación automática hasta 30 s"
  retry 15 2 systemctl is-active --quiet asterisk || die "Asterisk no se recuperó después del restart"
  log_ok "Asterisk se recuperó y está activo"
}

validate_runtime() {
  validate_modules
  local transports
  transports="$(asterisk -rx 'pjsip show transports')"
  grep -q 'transport-udp' <<<"$transports" || die "No aparece transport-udp en Asterisk"
  grep -q 'transport-tcp' <<<"$transports" || die "No aparece transport-tcp en Asterisk"
  asterisk -rx "dialplan show ${ECHO_EXTENSION}@from-internal" | grep -q "${ECHO_EXTENSION}" || die "No aparece Echo ${ECHO_EXTENSION}@from-internal"
  asterisk -rx "pjsip show endpoint ${SIP_EXTENSION}" | grep -q "Endpoint:.*${SIP_EXTENSION}" || die "No aparece endpoint SIP ${SIP_EXTENSION}"
}

ensure_secrets
mkdir -p "$ASTERISK_DIR"

rendered_http="$(render_template "$ROOT/config/asterisk/http.conf.template")"
rendered_ari="$(render_template "$ROOT/config/asterisk/ari.conf.template")"
rendered_pjsip="$(render_template "$ROOT/config/asterisk/pjsip.conf.template")"
rendered_extensions="$(render_template "$ROOT/config/asterisk/extensions.conf.template")"
rendered_ws="$(render_template "$ROOT/config/asterisk/websocket_client.conf.template")"

assert_no_existing_conflicts

if [[ "$RENDER_ONLY" == false ]]; then
  begin_transaction
fi

old_pjsip_block=""
if [[ -f "$ASTERISK_DIR/pjsip.conf" ]]; then
  old_pjsip_block="$(managed_block "$ASTERISK_DIR/pjsip.conf")"
fi
expected_transport_sig="$(transport_signature <<<"$rendered_pjsip")"
old_transport_sig="$(transport_signature <<<"$old_pjsip_block")"
transport_changed=false
[[ "$expected_transport_sig" == "$old_transport_sig" ]] || transport_changed=true

changed=false
apply_block "$ASTERISK_DIR/http.conf" "$rendered_http" true && changed=true || true
apply_block "$ASTERISK_DIR/ari.conf" "$rendered_ari" true && changed=true || true
apply_block "$ASTERISK_DIR/pjsip.conf" "$rendered_pjsip" false && changed=true || true
apply_block "$ASTERISK_DIR/extensions.conf" "$rendered_extensions" false && changed=true || true
apply_block "$ASTERISK_DIR/websocket_client.conf" "$rendered_ws" false && changed=true || true

if [[ "$RENDER_ONLY" == true ]]; then
  log_ok "Configuración renderizada en $ASTERISK_DIR"
  exit 0
fi

[[ $EUID -eq 0 ]] || die "La configuración real de Asterisk requiere root"
require_cmd systemctl
require_cmd asterisk

if [[ "$transport_changed" == true ]]; then
  log_info "Cambió la definición de transportes PJSIP: se requiere restart completo de Asterisk"
  restart_or_recover
elif [[ "$changed" == true ]]; then
  asterisk -rx 'core reload' >/dev/null
fi
validate_runtime
TXN_ACTIVE=false
log_ok "Asterisk configurado y validado"
