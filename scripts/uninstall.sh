#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"

YES=false
[[ "${1:-}" == "--yes" ]] && YES=true
[[ $# -le 1 ]] || die "Uso: scripts/uninstall.sh [--yes]"
[[ $EUID -eq 0 ]] || die "La desinstalación necesita root para Asterisk/systemd/firewall"

load_project_env
source <(bash "$ROOT/scripts/detect-system.sh" --env)
: "${SIP_PORT:=5060}"
: "${RTP_START:=10000}"
: "${RTP_END:=20000}"
: "${ARI_PORT:=8088}"
: "${OLLAMA_PORT:=11434}"
: "${INTEGRATION_NETWORK:=automation-net}"
BEGIN_MARKER='; BEGIN DOGRAH-LOCAL-VOICE-STACK'
END_MARKER='; END DOGRAH-LOCAL-VOICE-STACK'

if [[ "$YES" != true ]]; then
  cat <<'WARN'
Se quitarán SOLO recursos administrados por dograh-local-voice-stack:
- bloques marcados de Asterisk (con backup previo),
- reglas UFW que el proyecto registró como agregadas por él,
- override Ollama si coincide con el template administrado,
- contenedores Dograh (sin borrar volúmenes) y su checkout .runtime/dograh,
- automation-net solo si ya no tiene contenedores conectados.

NO se desinstalarán Docker, Asterisk ni Ollama preexistentes.
WARN
  read -r -p "¿Continuar? [escribí SI]: " answer
  [[ "$answer" == SI ]] || { echo "Cancelado"; exit 0; }
fi

strip_managed_block_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  grep -Fq "$BEGIN_MARKER" "$file" || return 0
  backup_file "$file"
  local tmp
  tmp="$(mktemp)"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0==begin {skip=1; next}
    $0==end {skip=0; next}
    !skip {print}
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

for conf in http.conf ari.conf pjsip.conf extensions.conf websocket_client.conf; do
  strip_managed_block_file "/etc/asterisk/$conf"
done
if systemctl is-active --quiet asterisk 2>/dev/null; then
  systemctl restart asterisk || log_warn "Asterisk no reinició limpio; revisá systemctl status asterisk"
fi

remove_ufw_rule_if_owned() {
  local flag="$1"
  shift
  if [[ "${!flag:-false}" == true ]] && command -v ufw >/dev/null 2>&1; then
    ufw --force delete "$@" >/dev/null 2>&1 || log_warn "No pude borrar regla UFW registrada: $*"
  fi
}
fw_lan="${FIREWALL_LAN_CIDR:-${LAN_CIDR:-}}"
fw_docker="${FIREWALL_DOCKER_SUBNET:-${DOGRAH_DOCKER_SUBNET:-}}"
[[ -n "$fw_lan" ]] && remove_ufw_rule_if_owned FIREWALL_RULE_SIP_ADDED allow from "$fw_lan" to any port "$SIP_PORT" proto udp
[[ -n "$fw_lan" ]] && remove_ufw_rule_if_owned FIREWALL_RULE_RTP_ADDED allow from "$fw_lan" to any port "${RTP_START}:${RTP_END}" proto udp
[[ -n "$fw_docker" ]] && remove_ufw_rule_if_owned FIREWALL_RULE_ARI_ADDED allow from "$fw_docker" to any port "$ARI_PORT" proto tcp
[[ -n "$fw_docker" ]] && remove_ufw_rule_if_owned FIREWALL_RULE_OLLAMA_ADDED allow from "$fw_docker" to any port "$OLLAMA_PORT" proto tcp

ollama_override=/etc/systemd/system/ollama.service.d/override.conf
if [[ -f "$ollama_override" ]]; then
  expected="$(sed "s/0\.0\.0\.0:11434/0.0.0.0:${OLLAMA_PORT}/" "$ROOT/config/ollama/override.conf")"
  if [[ "$(cat "$ollama_override")" == "$expected" ]]; then
    rm -f "$ollama_override"
    systemctl daemon-reload
    systemctl restart ollama 2>/dev/null || true
  else
    log_warn "No borro $ollama_override porque difiere del template del proyecto."
  fi
fi

if [[ -n "${DOGRAH_DIR:-}" && -d "${DOGRAH_DIR:-}" ]]; then
  if [[ -f "$DOGRAH_DIR/docker-compose.yaml" ]]; then
    (cd "$DOGRAH_DIR" && docker compose down) || log_warn "No pude detener completamente Dograh"
  fi
  rm -rf --one-file-system "$DOGRAH_DIR"
fi

if docker network inspect "$INTEGRATION_NETWORK" >/dev/null 2>&1; then
  attached="$(docker network inspect -f '{{len .Containers}}' "$INTEGRATION_NETWORK" 2>/dev/null || echo 1)"
  if [[ "$attached" == 0 ]]; then
    docker network rm "$INTEGRATION_NETWORK" >/dev/null
  else
    log_warn "No borro $INTEGRATION_NETWORK: todavía tiene $attached contenedor(es) conectado(s)."
  fi
fi

rm -f "$RUNTIME_DIR/secrets.env" "$RUNTIME_DIR/state.env" "$RUNTIME_DIR/install-state.env"
log_ok "Recursos administrados retirados. Los backups en .runtime/backups se conservaron."
