#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "${1:-}" in
  --json) exec "$ROOT/scripts/verify-stack.sh" --json ;;
  -h|--help) echo "Uso: scripts/doctor.sh [--json]"; exit 0 ;;
  "") ;;
  *) echo "Opción desconocida: ${1:-}" >&2; exit 2 ;;
esac

remedy() {
  case "$1" in
    system.os) echo "Usá Arch/CachyOS o Ubuntu/Debian." ;;
    system.docker) echo "Solución: ejecutá el instalador de tu plataforma y verificá 'docker info'." ;;
    asterisk.service) echo "Solución: revisá 'systemctl status asterisk' y docs/ASTERISK.md." ;;
    asterisk.sip_udp|asterisk.sip_tcp) echo "Solución: ./scripts/configure-asterisk.sh; después verificá 'pjsip show transports'." ;;
    asterisk.ari_http|asterisk.ari_auth) echo "Solución: verificá /etc/asterisk/http.conf, ari.conf y la regla Docker→8088; docs/ASTERISK.md." ;;
    asterisk.websocket_modules) echo "Solución: instalá/compilá Asterisk con los módulos WebSocket requeridos; docs/ASTERISK.md." ;;
    sip.endpoint_2001|sip.echo_600) echo "Solución: ./scripts/configure-asterisk.sh y repetí el checkpoint Linphone→600." ;;
    dograh.api_health) echo "Solución: revisá 'docker compose ps' y logs en .runtime/dograh; docs/DOGRAH.md." ;;
    dograh.ari_manager) echo "Solución: confirmá ENABLE_ARI_MANAGER=true y la configuración Asterisk Local en Dograh." ;;
    dograh.ari_websocket) echo "Solución: verificá ARI Endpoint, contraseña, websocket_client.conf Name y UFW Docker→8088." ;;
    ollama.api|ollama.model) echo "Solución: ./scripts/configure-ollama.sh; verificá listener 0.0.0.0:11434 y modelo." ;;
    ollama.from_dograh) echo "Solución: comprobá gateway/subnet automation-net y UFW Docker→11434." ;;
    firewall.*) echo "Solución: ./scripts/configure-firewall.sh; si no usás UFW, seguí docs/FIREWALL.md." ;;
    docker.dns_collision) echo "Solución: desconectá n8n/otros stacks de dograh_app-network; compartí solo automation-net." ;;
    *) echo "Solución: consultá docs/TROUBLESHOOTING.md." ;;
  esac
}

group_title=""
pass=0 warn=0 fail=0
output="$("$ROOT/scripts/verify-stack.sh" --tsv || true)"
while IFS=$'\t' read -r name status detail; do
  [[ -n "$name" ]] || continue
  group="${name%%.*}"
  if [[ "$group" != "$group_title" ]]; then
    group_title="$group"
    printf '\n== %s ==\n' "${group^^}"
  fi
  printf '[%-4s] %-30s %s\n' "$status" "$name" "$detail"
  case "$status" in
    PASS) pass=$((pass+1)) ;;
    WARN) warn=$((warn+1)); remedy "$name" ;;
    FAIL) fail=$((fail+1)); remedy "$name" ;;
  esac
done <<<"$output"

printf '\nResumen: %d PASS / %d WARN / %d FAIL\n' "$pass" "$warn" "$fail"
if (( fail == 0 )); then
  echo 'STACK LISTO PARA LOS CHECKS AUTOMÁTICOS. Falta confirmar audio humano: Linphone→600 y Dograh Test Call→2001.'
  exit 0
fi
exit 1
