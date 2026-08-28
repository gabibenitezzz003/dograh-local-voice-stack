#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"

usage() {
  cat <<'USAGE'
Uso: scripts/detect-system.sh [--env]
  --env  imprime variables KEY=value para consumo por otros scripts.
USAGE
}

[[ -r /etc/os-release ]] || die "No se puede leer /etc/os-release"
source /etc/os-release
OS_ID="${ID:-unknown}"
OS_LIKE="${ID_LIKE:-}"
case " $OS_ID $OS_LIKE " in
  *cachyos*|*arch*) OS_FAMILY=arch ;;
  *ubuntu*|*debian*) OS_FAMILY=debian ;;
  *) OS_FAMILY=unsupported ;;
esac

LAN_IP=""
LAN_IFACE=""
LAN_CIDR=""
if command -v ip >/dev/null 2>&1; then
  route_line="$(ip -4 route get 1.1.1.1 2>/dev/null | head -n1 || true)"
  LAN_IP="$(awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}' <<<"$route_line")"
  LAN_IFACE="$(awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}' <<<"$route_line")"
  if [[ -n "$LAN_IFACE" ]]; then
    LAN_CIDR="$(ip -4 route show dev "$LAN_IFACE" proto kernel scope link 2>/dev/null | awk '$1 ~ /^[0-9]+\./ && $1 ~ /\// {print $1; exit}')"
    if [[ -z "$LAN_CIDR" ]]; then
      LAN_CIDR="$(ip -o -4 addr show dev "$LAN_IFACE" scope global 2>/dev/null | awk '{print $4; exit}')"
    fi
  fi
fi

service_active() {
  command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$1" 2>/dev/null
}
FIREWALL=none
if service_active ufw; then
  FIREWALL=ufw
elif service_active firewalld; then
  FIREWALL=firewalld
elif service_active nftables; then
  FIREWALL=nftables
fi

DOCKER_AVAILABLE=false
if command -v docker >/dev/null 2>&1; then
  DOCKER_AVAILABLE=true
fi
NVIDIA_AVAILABLE=false
if command -v nvidia-smi >/dev/null 2>&1; then
  NVIDIA_AVAILABLE=true
fi

print_env() {
  printf 'OS_FAMILY=%s\n' "$OS_FAMILY"
  printf 'OS_ID=%s\n' "$OS_ID"
  printf 'LAN_IP=%s\n' "$LAN_IP"
  printf 'LAN_IFACE=%s\n' "$LAN_IFACE"
  printf 'LAN_CIDR=%s\n' "$LAN_CIDR"
  printf 'FIREWALL=%s\n' "$FIREWALL"
  printf 'DOCKER_AVAILABLE=%s\n' "$DOCKER_AVAILABLE"
  printf 'NVIDIA_AVAILABLE=%s\n' "$NVIDIA_AVAILABLE"
}

case "${1:-}" in
  --env) print_env ;;
  -h|--help) usage ;;
  "")
    printf 'Sistema: %s (%s)\n' "$OS_ID" "$OS_FAMILY"
    printf 'LAN: %s (%s) %s\n' "${LAN_IP:-no detectada}" "${LAN_IFACE:-sin interfaz}" "${LAN_CIDR:-sin CIDR}"
    printf 'Firewall: %s\nDocker: %s\nNVIDIA: %s\n' "$FIREWALL" "$DOCKER_AVAILABLE" "$NVIDIA_AVAILABLE"
    ;;
  *) usage; exit 2 ;;
esac
