#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"

load_project_env
source <(bash "$ROOT/scripts/detect-system.sh" --env)
: "${SIP_PORT:=5060}"
: "${RTP_START:=10000}"
: "${RTP_END:=20000}"
: "${ARI_PORT:=8088}"
: "${OLLAMA_PORT:=11434}"
STATE_FILE="$RUNTIME_DIR/state.env"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ $# -le 1 ]] || die "Uso: scripts/configure-firewall.sh [--dry-run]"

if [[ "$DRY_RUN" == true ]]; then
  : "${LAN_CIDR:=<LAN_CIDR_detectada_en_runtime>}"
  : "${DOGRAH_DOCKER_SUBNET:=<DOGRAH_DOCKER_SUBNET_detectada_en_runtime>}"
else
  [[ -n "${LAN_CIDR:-}" ]] || die "No pude detectar LAN_CIDR"
  [[ -n "${DOGRAH_DOCKER_SUBNET:-}" ]] || die "Falta DOGRAH_DOCKER_SUBNET. Ejecutá primero scripts/configure-dograh.sh"
fi

if [[ "$FIREWALL" == firewalld || "$FIREWALL" == nftables ]]; then
  log_warn "Firewall detectado: $FIREWALL. No modificaré políticas desconocidas. Seguí docs/FIREWALL.md."
  exit 0
fi
if [[ "$DRY_RUN" == false ]]; then
  command -v ufw >/dev/null 2>&1 || die "UFW no está instalado. Instalalo o seguí docs/FIREWALL.md para tu firewall."
fi

ufw_has_rule() {
  local needle_port="$1" source="$2"
  ufw status 2>/dev/null | grep -F "$needle_port" | grep -F "$source" >/dev/null 2>&1
}

apply_rule() {
  local label="$1" needle="$2" source="$3" state_key="$4"
  shift 4
  if [[ "$DRY_RUN" == true ]]; then
    printf '+ ufw '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  if ufw_has_rule "$needle" "$source"; then
    log_ok "$label ya existe"
    return 0
  fi
  ufw "$@"
  write_env_value "$STATE_FILE" "$state_key" true
}

if [[ "$DRY_RUN" == false ]]; then
  write_env_value "$STATE_FILE" FIREWALL_LAN_CIDR "$LAN_CIDR"
  write_env_value "$STATE_FILE" FIREWALL_DOCKER_SUBNET "$DOGRAH_DOCKER_SUBNET"
fi

apply_rule "SIP UDP LAN" "${SIP_PORT}/udp" "$LAN_CIDR" FIREWALL_RULE_SIP_ADDED allow from "$LAN_CIDR" to any port "$SIP_PORT" proto udp
apply_rule "RTP LAN" "${RTP_START}:${RTP_END}/udp" "$LAN_CIDR" FIREWALL_RULE_RTP_ADDED allow from "$LAN_CIDR" to any port "${RTP_START}:${RTP_END}" proto udp
apply_rule "Dograh → ARI" "${ARI_PORT}/tcp" "$DOGRAH_DOCKER_SUBNET" FIREWALL_RULE_ARI_ADDED allow from "$DOGRAH_DOCKER_SUBNET" to any port "$ARI_PORT" proto tcp
apply_rule "Dograh → Ollama" "${OLLAMA_PORT}/tcp" "$DOGRAH_DOCKER_SUBNET" FIREWALL_RULE_OLLAMA_ADDED allow from "$DOGRAH_DOCKER_SUBNET" to any port "$OLLAMA_PORT" proto tcp

if [[ "$DRY_RUN" == false ]]; then
  if ufw status | head -n1 | grep -q 'inactive'; then
    log_warn "Las reglas quedaron cargadas pero UFW está inactivo. No lo habilito automáticamente para no cortar acceso remoto; revisá docs/FIREWALL.md."
  else
    log_ok "Reglas UFW aplicadas con alcance mínimo"
  fi
fi
