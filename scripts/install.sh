#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"

PHASES=(preflight platform asterisk sip_checkpoint network firewall dograh ari_checkpoint ollama final_verify)
DRY_RUN=false
RESUME=false

usage() {
  cat <<'USAGE'
Uso: sudo ./scripts/install.sh [--dry-run] [--resume]

--dry-run  muestra acciones principales sin modificar el sistema.
--resume   salta fases marcadas como completas solo si su verificación sigue pasando.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --resume) RESUME=true ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opción desconocida: $1" ;;
  esac
  shift
done

if [[ "$DRY_RUN" == false && $EUID -ne 0 ]]; then
  die "La instalación modifica systemd/Asterisk/firewall: ejecutá con sudo."
fi

ensure_runtime_dirs
STATE_FILE="$RUNTIME_DIR/install-state.env"
PROJECT_STATE="$RUNTIME_DIR/state.env"
load_project_env
source <(bash "$ROOT/scripts/detect-system.sh" --env)

phase_key() { printf 'PHASE_%s' "${1^^}"; }
phase_mark_done() { write_env_value "$STATE_FILE" "$(phase_key "$1")" done; }
phase_was_done() {
  [[ -f "$STATE_FILE" ]] || return 1
  grep -qE "^$(phase_key "$1")=done$" "$STATE_FILE"
}

ask_yes() {
  local prompt="$1"
  if [[ ! -t 0 ]]; then
    die "$prompt (se requiere terminal interactiva)"
  fi
  local answer
  read -r -p "$prompt [s/N]: " answer
  [[ "$answer" =~ ^[sSyY]$ ]]
}

port_owner_ok() {
  local port="$1" expected_regex="$2"
  local line
  line="$(ss -ltnup 2>/dev/null | grep -E "[:.]${port}[[:space:]]" || true)"
  [[ -z "$line" ]] && return 0
  grep -Eqi "$expected_regex" <<<"$line"
}

phase_valid() {
  local phase="$1"
  load_project_env
  case "$phase" in
    preflight) [[ "$OS_FAMILY" == arch || "$OS_FAMILY" == debian ]] && command -v systemctl >/dev/null 2>&1 ;;
    platform) command -v docker >/dev/null 2>&1 && command -v asterisk >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 ;;
    asterisk) systemctl is-active --quiet asterisk 2>/dev/null && asterisk -rx "pjsip show endpoint ${SIP_EXTENSION:-2001}" 2>/dev/null | grep -q "Endpoint:.*${SIP_EXTENSION:-2001}" ;;
    sip_checkpoint) phase_was_done sip_checkpoint && asterisk -rx "dialplan show ${ECHO_EXTENSION:-600}@from-internal" 2>/dev/null | grep -q "${ECHO_EXTENSION:-600}" ;;
    network) docker network inspect "${INTEGRATION_NETWORK:-automation-net}" >/dev/null 2>&1 ;;
    firewall) [[ -n "${DOGRAH_DOCKER_SUBNET:-}" ]] && { ! command -v ufw >/dev/null 2>&1 || ufw status >/dev/null 2>&1; } ;;
    dograh) curl -fsS --max-time 3 "http://127.0.0.1:${DOGRAH_API_PORT:-8000}/api/v1/health" >/dev/null 2>&1 ;;
    ari_checkpoint) [[ -n "${DOGRAH_API_CONTAINER:-}" ]] && docker logs "$DOGRAH_API_CONTAINER" 2>&1 | grep -q 'WebSocket connected to' ;;
    ollama) curl -fsS --max-time 3 "http://127.0.0.1:${OLLAMA_PORT:-11434}/v1/models" 2>/dev/null | grep -Fq "${OLLAMA_MODEL:-qwen2.5:7b-instruct-q5_K_M}" ;;
    final_verify) "$ROOT/scripts/verify-stack.sh" --tsv >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

run_phase() {
  local phase="$1"
  if [[ "$RESUME" == true ]] && phase_was_done "$phase" && phase_valid "$phase"; then
    log_ok "Fase $phase ya estaba completa y sigue válida; se omite"
    return 0
  fi

  log_info "===== FASE: $phase ====="
  case "$phase" in
    preflight)
      [[ "$OS_FAMILY" == arch || "$OS_FAMILY" == debian ]] || die "OS no soportado: $OS_ID"
      command -v systemctl >/dev/null 2>&1 || die "systemd/systemctl es requerido"
      command -v ss >/dev/null 2>&1 || die "Falta ss/iproute2"
      if command -v docker >/dev/null 2>&1 && docker info 2>/dev/null | grep -qi rootless; then
        die "Docker rootless no está soportado por este flujo de host networking/firewall."
      fi
      port_owner_ok 5060 'asterisk' || die "Puerto 5060 ocupado por un proceso que no parece Asterisk"
      port_owner_ok 8088 'asterisk' || die "Puerto 8088 ocupado por un proceso que no parece Asterisk"
      port_owner_ok 11434 'ollama' || die "Puerto 11434 ocupado por un proceso que no parece Ollama"
      port_owner_ok 8000 'docker|containerd|podman' || die "Puerto 8000 ocupado por un servicio incompatible"
      port_owner_ok 3010 'docker|containerd|podman' || die "Puerto 3010 ocupado por un servicio incompatible"
      log_ok "Preflight básico correcto"
      ;;
    platform)
      if [[ "$DRY_RUN" == true ]]; then bash "$ROOT/scripts/install-${OS_FAMILY}.sh" --dry-run; else bash "$ROOT/scripts/install-${OS_FAMILY}.sh"; fi
      ;;
    asterisk)
      if [[ "$DRY_RUN" == true ]]; then
        tmp="$(mktemp -d)"
        RUNTIME_DIR="$(mktemp -d)" bash "$ROOT/scripts/configure-asterisk.sh" --render-only "$tmp"
        rm -rf "$tmp"
      else
        bash "$ROOT/scripts/configure-asterisk.sh"
      fi
      ;;
    sip_checkpoint)
      if [[ "$DRY_RUN" == true ]]; then
        echo "CHECKPOINT: configurar Linphone con extensión 2001 y llamar al 600."
      else
        load_project_env
        source <(bash "$ROOT/scripts/detect-system.sh" --env)
        cat <<INFO

CHECKPOINT SIP / AUDIO
----------------------
En Linphone configurá:
  Usuario:        ${SIP_EXTENSION:-2001}
  Auth username:  ${SIP_EXTENSION:-2001}
  Servidor:       ${LAN_IP}
  Puerto:         ${SIP_PORT:-5060}
  Transporte:     UDP

Para ver SOLO la clave SIP:
  sudo awk -F= '$1=="SIP_PASSWORD"{print $2}' "$RUNTIME_DIR/secrets.env"

Después llamá a: ${ECHO_EXTENSION:-600}
Tenés que escucharte a vos mismo.
INFO
        ask_yes "¿Te escuchaste correctamente al llamar al ${ECHO_EXTENSION:-600}?" || die "No continúo hasta que Echo() funcione. Ejecutá ./scripts/doctor.sh y revisá docs/TROUBLESHOOTING.md."
      fi
      ;;
    network)
      if [[ "$DRY_RUN" == true ]]; then
        echo "+ docker network create ${INTEGRATION_NETWORK:-automation-net} (si falta)"
      else
        command -v docker >/dev/null 2>&1 || die "Docker no disponible"
        net="${INTEGRATION_NETWORK:-automation-net}"
        docker network inspect "$net" >/dev/null 2>&1 || docker network create "$net" >/dev/null
        subnet="$(docker network inspect -f '{{(index .IPAM.Config 0).Subnet}}' "$net")"
        gateway="$(docker network inspect -f '{{(index .IPAM.Config 0).Gateway}}' "$net")"
        write_env_value "$PROJECT_STATE" INTEGRATION_NETWORK "$net"
        write_env_value "$PROJECT_STATE" DOGRAH_DOCKER_SUBNET "$subnet"
        write_env_value "$PROJECT_STATE" DOGRAH_DOCKER_GATEWAY "$gateway"
        log_ok "Red $net: $subnet gateway $gateway"
      fi
      ;;
    firewall)
      if [[ "$DRY_RUN" == true ]]; then bash "$ROOT/scripts/configure-firewall.sh" --dry-run; else bash "$ROOT/scripts/configure-firewall.sh"; fi
      ;;
    dograh)
      if [[ "$DRY_RUN" == true ]]; then bash "$ROOT/scripts/configure-dograh.sh" --dry-run; else bash "$ROOT/scripts/configure-dograh.sh"; fi
      ;;
    ari_checkpoint)
      if [[ "$DRY_RUN" == true ]]; then
        echo "CHECKPOINT: crear Asterisk Local en Dograh y validar ARI WebSocket."
      else
        load_project_env
        cat <<INFO

CHECKPOINT DOGRAH / ASTERISK ARI
--------------------------------
Abrí: http://localhost:${DOGRAH_UI_PORT:-3010}
Telephony -> Add configuration -> Asterisk ARI

  Name:                       Asterisk Local
  ARI Endpoint:               http://${DOGRAH_DOCKER_GATEWAY}:${ARI_PORT:-8088}
  Stasis App Name:            dograh
  ARI Password:               [leer ARI_PASSWORD con el comando de abajo]
  websocket_client.conf Name: dograh

Para ver SOLO la clave ARI:
  sudo awk -F= '$1=="ARI_PASSWORD"{print $2}' "$RUNTIME_DIR/secrets.env"

Luego agregá un Caller ID local, por ejemplo 1002.
Para la llamada de prueba: "Use SIP endpoint instead" -> destino ${SIP_EXTENSION:-2001}.
INFO
        ask_yes "¿Guardaste la configuración Asterisk Local en Dograh?" || die "Configurá Asterisk Local antes de continuar."
        load_project_env
        [[ -n "${DOGRAH_API_CONTAINER:-}" ]] || die "Falta DOGRAH_API_CONTAINER"
        if ! retry 45 2 bash -c "docker logs '$DOGRAH_API_CONTAINER' 2>&1 | grep -q 'WebSocket connected to'"; then
          die "Dograh no confirmó WebSocket ARI. Ejecutá ./scripts/doctor.sh y revisá firewall/credenciales."
        fi
        log_ok "Dograh confirmó WebSocket ARI"
      fi
      ;;
    ollama)
      if [[ "$DRY_RUN" == true ]]; then bash "$ROOT/scripts/configure-ollama.sh" --dry-run; else bash "$ROOT/scripts/configure-ollama.sh"; fi
      ;;
    final_verify)
      if [[ "$DRY_RUN" == true ]]; then echo "+ ./scripts/verify-stack.sh --tsv"; else "$ROOT/scripts/doctor.sh"; fi
      ;;
  esac

  [[ "$DRY_RUN" == true ]] || phase_mark_done "$phase"
}

for phase in "${PHASES[@]}"; do
  run_phase "$phase"
done

cat <<'DONE'

Instalación terminada.
Checkpoints manuales que deben quedar confirmados:
  1) Linphone -> 600: te escuchás.
  2) Dograh Test Call -> "Use SIP endpoint instead" -> 2001: el teléfono suena y hay audio bidireccional.

Los secretos NO se muestran en el resumen. Consultá docs/SECURITY.md para leer/rotar uno puntual.
DONE
