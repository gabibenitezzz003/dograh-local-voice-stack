#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"

load_project_env
source <(bash "$ROOT/scripts/detect-system.sh" --env)
: "${SIP_EXTENSION:=2001}"
: "${ECHO_EXTENSION:=600}"
: "${SIP_PORT:=5060}"
: "${RTP_START:=10000}"
: "${RTP_END:=20000}"
: "${ARI_PORT:=8088}"
: "${DOGRAH_API_PORT:=8000}"
: "${OLLAMA_PORT:=11434}"
: "${OLLAMA_MODEL:=qwen2.5:7b-instruct-q5_K_M}"

OUTPUT=tsv
case "${1:-}" in
  --json) OUTPUT=json ;;
  --tsv|"") OUTPUT=tsv ;;
  -h|--help)
    echo "Uso: scripts/verify-stack.sh [--json|--tsv]"
    exit 0
    ;;
  *) die "Opción desconocida: ${1:-}" ;;
esac

names=()
statuses=()
details=()
fail_count=0

add_check() {
  local name="$1" status="$2" detail="$3"
  names+=("$name")
  statuses+=("$status")
  details+=("$detail")
  if [[ "$status" == FAIL ]]; then fail_count=$((fail_count + 1)); fi
}

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/}
  printf '%s' "$s"
}

asterisk_cmd() {
  command -v asterisk >/dev/null 2>&1 || return 127
  asterisk -rx "$1" 2>/dev/null
}

if [[ "$OS_FAMILY" == arch || "$OS_FAMILY" == debian ]]; then
  add_check system.os PASS "$OS_ID ($OS_FAMILY)"
else
  add_check system.os FAIL "$OS_ID no soportado"
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  add_check system.docker PASS "Docker daemon accesible"
else
  add_check system.docker FAIL "Docker no está instalado, no corre o el usuario no tiene acceso"
fi

if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet asterisk 2>/dev/null; then
  add_check asterisk.service PASS "asterisk.service active"
else
  add_check asterisk.service FAIL "asterisk.service no está active"
fi

if command -v ss >/dev/null 2>&1 && ss -lun 2>/dev/null | grep -Eq "[:.]${SIP_PORT}[[:space:]]"; then
  add_check asterisk.sip_udp PASS "UDP ${SIP_PORT} escuchando"
else
  add_check asterisk.sip_udp FAIL "No detecto listener UDP ${SIP_PORT}"
fi
if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -Eq "[:.]${SIP_PORT}[[:space:]]"; then
  add_check asterisk.sip_tcp PASS "TCP ${SIP_PORT} escuchando"
else
  add_check asterisk.sip_tcp FAIL "No detecto listener TCP ${SIP_PORT}"
fi

ari_http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:${ARI_PORT}/ari/asterisk/info" 2>/dev/null || true)"
if [[ "$ari_http_code" == 401 ]]; then
  add_check asterisk.ari_http PASS "ARI responde 401 sin credenciales (esperado)"
elif [[ "$ari_http_code" == 200 ]]; then
  add_check asterisk.ari_http WARN "ARI responde 200 sin credenciales; revisá exposición/autenticación"
else
  add_check asterisk.ari_http FAIL "ARI no responde correctamente en ${ARI_PORT} (HTTP ${ari_http_code:-sin respuesta})"
fi
if [[ -n "${ARI_PASSWORD:-}" ]]; then
  ari_auth_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 -u "dograh:${ARI_PASSWORD}" "http://127.0.0.1:${ARI_PORT}/ari/asterisk/info" 2>/dev/null || true)"
  [[ "$ari_auth_code" == 200 ]] && add_check asterisk.ari_auth PASS "ARI autenticado HTTP 200" || add_check asterisk.ari_auth FAIL "ARI autenticado devolvió HTTP ${ari_auth_code:-sin respuesta}"
else
  add_check asterisk.ari_auth FAIL "No encuentro ARI_PASSWORD en .runtime/secrets.env"
fi

modules_ok=true
for module in res_ari.so chan_websocket.so res_http_websocket.so res_pjsip_transport_websocket.so res_websocket_client.so; do
  if ! asterisk_cmd "module show like $module" | grep -q "$module"; then modules_ok=false; fi
done
[[ "$modules_ok" == true ]] && add_check asterisk.websocket_modules PASS "Módulos ARI/WebSocket cargados" || add_check asterisk.websocket_modules FAIL "Falta al menos un módulo ARI/WebSocket requerido"

if asterisk_cmd "pjsip show endpoint ${SIP_EXTENSION}" | grep -q "Endpoint:.*${SIP_EXTENSION}"; then
  add_check sip.endpoint_2001 PASS "Endpoint ${SIP_EXTENSION} configurado"
else
  add_check sip.endpoint_2001 FAIL "Endpoint ${SIP_EXTENSION} no aparece en PJSIP"
fi
if asterisk_cmd "dialplan show ${ECHO_EXTENSION}@from-internal" | grep -q "${ECHO_EXTENSION}"; then
  add_check sip.echo_600 PASS "Echo ${ECHO_EXTENSION}@from-internal configurado"
else
  add_check sip.echo_600 FAIL "No aparece Echo ${ECHO_EXTENSION}@from-internal"
fi
if contacts="$(asterisk_cmd 'pjsip show contacts' || true)" && grep -q "${SIP_EXTENSION}/sip:" <<<"$contacts"; then
  :
else
  details[${#details[@]}-1]="${details[${#details[@]}-1]} (teléfono ${SIP_EXTENSION} no está registrado ahora)"
fi

if curl -fsS --max-time 5 "http://127.0.0.1:${DOGRAH_API_PORT}/api/v1/health" >/dev/null 2>&1; then
  add_check dograh.api_health PASS "Dograh API HTTP 200"
else
  add_check dograh.api_health FAIL "Dograh API no responde en ${DOGRAH_API_PORT}"
fi

if [[ -n "${DOGRAH_API_CONTAINER:-}" ]] && docker inspect "$DOGRAH_API_CONTAINER" >/dev/null 2>&1; then
  dograh_logs="$(docker logs "$DOGRAH_API_CONTAINER" 2>&1 || true)"
  if grep -q '\[ARI Manager\] Active connections:' <<<"$dograh_logs"; then
    add_check dograh.ari_manager PASS "ARI Manager administra al menos una configuración"
  else
    add_check dograh.ari_manager FAIL "No encuentro actividad de ARI Manager en logs Dograh"
  fi
  current_ari_estab=false
  if command -v ss >/dev/null 2>&1 && ss -tn 2>/dev/null | grep -q 'ESTAB' && ss -tn 2>/dev/null | grep -Eq "[:.]${ARI_PORT}[[:space:]]"; then current_ari_estab=true; fi
  if grep -q 'WebSocket connected to' <<<"$dograh_logs" && [[ "$current_ari_estab" == true ]]; then
    add_check dograh.ari_websocket PASS "Log WebSocket connected + TCP ESTAB hacia ARI"
  else
    add_check dograh.ari_websocket FAIL "Falta evidencia conjunta de WebSocket conectado y TCP ESTAB hacia :${ARI_PORT}"
  fi
else
  add_check dograh.ari_manager FAIL "No encuentro contenedor API Dograh válido en state.env"
  add_check dograh.ari_websocket FAIL "Sin contenedor Dograh no puedo validar WebSocket ARI"
fi

if curl -fsS --max-time 5 "http://127.0.0.1:${OLLAMA_PORT}/v1/models" >/dev/null 2>&1; then
  add_check ollama.api PASS "Ollama OpenAI API responde"
  models_body="$(curl -fsS --max-time 5 "http://127.0.0.1:${OLLAMA_PORT}/v1/models" 2>/dev/null || true)"
  grep -Fq "$OLLAMA_MODEL" <<<"$models_body" && add_check ollama.model PASS "$OLLAMA_MODEL disponible" || add_check ollama.model FAIL "$OLLAMA_MODEL no aparece en /v1/models"
else
  add_check ollama.api FAIL "Ollama no responde en ${OLLAMA_PORT}"
  add_check ollama.model FAIL "No puedo comprobar modelo sin API Ollama"
fi

if [[ -n "${DOGRAH_API_CONTAINER:-}" && -n "${DOGRAH_DOCKER_GATEWAY:-}" ]] && docker inspect "$DOGRAH_API_CONTAINER" >/dev/null 2>&1; then
  if docker exec -e TEST_URL="http://${DOGRAH_DOCKER_GATEWAY}:${OLLAMA_PORT}/v1/models" "$DOGRAH_API_CONTAINER" python -c 'import os,urllib.request; r=urllib.request.urlopen(os.environ["TEST_URL"],timeout=5); assert r.status==200' >/dev/null 2>&1; then
    add_check ollama.from_dograh PASS "Dograh alcanza Ollama por gateway Docker"
  else
    add_check ollama.from_dograh FAIL "Dograh no alcanza Ollama por ${DOGRAH_DOCKER_GATEWAY}:${OLLAMA_PORT}"
  fi
else
  add_check ollama.from_dograh FAIL "Falta contenedor/gateway Dograh para probar Ollama"
fi

ufw_active=false
ufw_text=""
if command -v ufw >/dev/null 2>&1; then
  ufw_text="$(ufw status 2>/dev/null || true)"
  grep -q '^Status: active' <<<"$ufw_text" && ufw_active=true
fi
firewall_rule_check() {
  local check="$1" needle="$2" source="$3"
  if [[ "$ufw_active" != true ]]; then
    add_check "$check" WARN "UFW no está activo; verificá tu firewall manualmente"
  elif grep -F "$needle" <<<"$ufw_text" | grep -Fq "$source"; then
    add_check "$check" PASS "$needle permitido desde $source"
  else
    add_check "$check" FAIL "No encuentro regla $needle desde $source"
  fi
}
firewall_rule_check firewall.sip "${SIP_PORT}/udp" "${LAN_CIDR:-LAN_NO_DETECTADA}"
firewall_rule_check firewall.rtp "${RTP_START}:${RTP_END}/udp" "${LAN_CIDR:-LAN_NO_DETECTADA}"
firewall_rule_check firewall.ari "${ARI_PORT}/tcp" "${DOGRAH_DOCKER_SUBNET:-DOCKER_NO_DETECTADA}"
firewall_rule_check firewall.ollama "${OLLAMA_PORT}/tcp" "${DOGRAH_DOCKER_SUBNET:-DOCKER_NO_DETECTADA}"

collision=""
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  while read -r cid; do
    [[ -n "$cid" ]] || continue
    project="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$cid" 2>/dev/null || true)"
    name="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')"
    while read -r net; do
      if [[ "$net" == *dograh*app-network* && "$project" != dograh ]]; then
        collision+="${name}:${net} "
      fi
    done < <(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$cid" 2>/dev/null || true)
  done < <(docker ps -q)
fi
[[ -z "$collision" ]] && add_check docker.dns_collision PASS "No detecto contenedores ajenos dentro de dograh app-network" || add_check docker.dns_collision FAIL "Riesgo de colisión DNS: $collision"

if [[ "$OUTPUT" == json ]]; then
  printf '['
  for i in "${!names[@]}"; do
    (( i > 0 )) && printf ','
    printf '{"name":"%s","status":"%s","detail":"%s"}' "$(json_escape "${names[$i]}")" "$(json_escape "${statuses[$i]}")" "$(json_escape "${details[$i]}")"
  done
  printf ']\n'
else
  for i in "${!names[@]}"; do
    printf '%s\t%s\t%s\n' "${names[$i]}" "${statuses[$i]}" "${details[$i]}"
  done
fi

(( fail_count == 0 ))
