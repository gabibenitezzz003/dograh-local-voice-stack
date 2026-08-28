#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"

load_project_env
: "${INTEGRATION_NETWORK:=automation-net}"
: "${DOGRAH_API_PORT:=8000}"
: "${DOGRAH_UI_PORT:=3010}"
DOGRAH_DIR="${DOGRAH_DIR:-$RUNTIME_DIR/dograh}"
DOGRAH_REPO="https://github.com/dograh-hq/dograh.git"
OVERRIDE_FILE="$ROOT/config/dograh/docker-compose.override.yml"
STATE_FILE="$RUNTIME_DIR/state.env"
DRY_RUN=false

usage() {
  cat <<'USAGE'
Uso: scripts/configure-dograh.sh [--dry-run]

Clona/actualiza Dograh, genera su .env mediante el helper upstream,
crea la red Docker de integración, levanta el stack y valida API/UI.
USAGE
}
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ $# -le 1 ]] || { usage; exit 2; }

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

if [[ "$DOGRAH_API_PORT" != 8000 || "$DOGRAH_UI_PORT" != 3010 ]]; then
  die "La primera versión soporta los puertos upstream de Dograh 8000/3010. Ajustá esos valores o revisá docs/DOGRAH.md para personalizar mappings."
fi

if [[ "$DRY_RUN" == false ]]; then
  require_cmd git
  require_cmd docker
  if ! docker compose version >/dev/null 2>&1; then
    die "Docker Compose v2 no está disponible (se requiere 'docker compose')"
  fi
fi
ensure_runtime_dirs

if [[ ! -d "$DOGRAH_DIR/.git" ]]; then
  run git clone --depth 1 "$DOGRAH_REPO" "$DOGRAH_DIR"
else
  if [[ "$DRY_RUN" == true ]]; then
    printf '+ git -C %q fetch --depth 1 origin main\n' "$DOGRAH_DIR"
    printf '+ git -C %q reset --keep origin/main\n' "$DOGRAH_DIR"
  else
    git -C "$DOGRAH_DIR" fetch --depth 1 origin main
    if git -C "$DOGRAH_DIR" diff --quiet -- . ':(exclude).env'; then
      git -C "$DOGRAH_DIR" reset --keep origin/main
    else
      log_warn "Checkout Dograh tiene cambios trackeados; no lo actualizo automáticamente."
    fi
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '+ docker network inspect %q || docker network create %q\n' "$INTEGRATION_NETWORK" "$INTEGRATION_NETWORK"
elif ! docker network inspect "$INTEGRATION_NETWORK" >/dev/null 2>&1; then
  docker network create "$INTEGRATION_NETWORK"
fi

if [[ "$DRY_RUN" == false ]]; then
  [[ -f "$DOGRAH_DIR/docker-compose.yaml" ]] || die "Dograh no contiene docker-compose.yaml"
  [[ -x "$DOGRAH_DIR/scripts/start_docker.sh" ]] || chmod +x "$DOGRAH_DIR/scripts/start_docker.sh"
  (
    cd "$DOGRAH_DIR"
    ENABLE_TELEMETRY=false REGISTRY=ghcr.io/dograh-hq ./scripts/start_docker.sh </dev/null
  )
  write_env_value "$DOGRAH_DIR/.env" REGISTRY ghcr.io/dograh-hq
  write_env_value "$DOGRAH_DIR/.env" ENABLE_TELEMETRY false
  write_env_value "$DOGRAH_DIR/.env" ENABLE_ARI_MANAGER true
  write_env_value "$DOGRAH_DIR/.env" INTEGRATION_NETWORK "$INTEGRATION_NETWORK"
  if grep -q '^BACKEND_API_ENDPOINT=http://localhost:8000$' "$DOGRAH_DIR/.env" 2>/dev/null; then
    log_warn "BACKEND_API_ENDPOINT está fijado a localhost. Si la UI muestra 'Backend connection failed', seguí docs/TROUBLESHOOTING.md#dograh-backend-connection-failed."
  fi
else
  printf '+ (cd %q && ENABLE_TELEMETRY=false REGISTRY=ghcr.io/dograh-hq ./scripts/start_docker.sh </dev/null)\n' "$DOGRAH_DIR"
fi

compose() {
  (cd "$DOGRAH_DIR" && INTEGRATION_NETWORK="$INTEGRATION_NETWORK" docker compose -f docker-compose.yaml -f "$OVERRIDE_FILE" "$@")
}

if [[ "$DRY_RUN" == true ]]; then
  printf '+ docker compose -f docker-compose.yaml -f %q up -d --pull always\n' "$OVERRIDE_FILE"
  exit 0
fi

compose up -d --pull always

api_container="$(compose ps -q api)"
[[ -n "$api_container" ]] || die "No se encontró el contenedor del servicio api de Dograh"
ui_container="$(compose ps -q ui)"
[[ -n "$ui_container" ]] || die "No se encontró el contenedor del servicio ui de Dograh"

retry 60 2 curl -fsS "http://127.0.0.1:${DOGRAH_API_PORT}/api/v1/health" >/dev/null || die "Dograh API no alcanzó HTTP 200"
retry 60 2 curl -fsS "http://127.0.0.1:${DOGRAH_UI_PORT}/" >/dev/null || die "Dograh UI no respondió"

network_subnet="$(docker network inspect -f '{{(index .IPAM.Config 0).Subnet}}' "$INTEGRATION_NETWORK")"
network_gateway="$(docker network inspect -f '{{(index .IPAM.Config 0).Gateway}}' "$INTEGRATION_NETWORK")"
api_ip="$(docker inspect -f "{{with index .NetworkSettings.Networks \"$INTEGRATION_NETWORK\"}}{{.IPAddress}}{{end}}" "$api_container")"
[[ -n "$network_subnet" && -n "$network_gateway" && -n "$api_ip" ]] || die "No pude resolver subnet/gateway/IP API de la red de integración"

write_env_value "$STATE_FILE" DOGRAH_DIR "$DOGRAH_DIR"
write_env_value "$STATE_FILE" DOGRAH_API_CONTAINER "$api_container"
write_env_value "$STATE_FILE" DOGRAH_API_IP "$api_ip"
write_env_value "$STATE_FILE" DOGRAH_DOCKER_SUBNET "$network_subnet"
write_env_value "$STATE_FILE" DOGRAH_DOCKER_GATEWAY "$network_gateway"
write_env_value "$STATE_FILE" INTEGRATION_NETWORK "$INTEGRATION_NETWORK"

log_ok "Dograh API HTTP 200 y UI disponible"
log_ok "Red $INTEGRATION_NETWORK: subnet=$network_subnet gateway=$network_gateway api=$api_ip"
