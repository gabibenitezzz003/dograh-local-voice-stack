#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"

load_project_env
: "${OLLAMA_PORT:=11434}"
: "${OLLAMA_MODEL:=qwen2.5:7b-instruct-q5_K_M}"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ $# -le 1 ]] || die "Uso: scripts/configure-ollama.sh [--dry-run]"

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

install_ollama() {
  command -v ollama >/dev/null 2>&1 && return 0
  ensure_runtime_dirs
  local installer="$RUNTIME_DIR/ollama-install.sh"
  log_info "Ollama no está instalado. Descargando instalador oficial: https://ollama.com/install.sh"
  if [[ "$DRY_RUN" == true ]]; then
    printf '+ curl -fsSL https://ollama.com/install.sh -o %q\n' "$installer"
    printf '+ sh %q\n' "$installer"
    return 0
  fi
  require_cmd curl
  curl -fsSL https://ollama.com/install.sh -o "$installer"
  chmod 700 "$installer"
  sh "$installer"
}

install_ollama
if [[ "$DRY_RUN" == false ]]; then
  [[ $EUID -eq 0 ]] || die "Configurar el servicio Ollama requiere root"
fi

override_src="$ROOT/config/ollama/override.conf"
override_dst="/etc/systemd/system/ollama.service.d/override.conf"
if [[ "$DRY_RUN" == true ]]; then
  printf '+ mkdir -p /etc/systemd/system/ollama.service.d\n'
  printf '+ instalar override OLLAMA_HOST=0.0.0.0:%s\n' "$OLLAMA_PORT"
  printf '+ systemctl daemon-reload && systemctl restart ollama\n'
else
  mkdir -p "$(dirname "$override_dst")"
  sed "s/0\.0\.0\.0:11434/0.0.0.0:${OLLAMA_PORT}/" "$override_src" > "$override_dst"
  systemctl daemon-reload
  systemctl enable ollama >/dev/null 2>&1 || true
  systemctl restart ollama
  retry 15 2 bash -c "ss -ltn | grep -Eq '[[:space:]]0\\.0\\.0\\.0:${OLLAMA_PORT}[[:space:]]'" || die "Ollama no escucha en 0.0.0.0:${OLLAMA_PORT}"
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '+ ollama pull %q (solo si falta)\n' "$OLLAMA_MODEL"
  exit 0
fi

if ! ollama list | awk 'NR>1 {print $1}' | grep -Fxq "$OLLAMA_MODEL"; then
  ollama pull "$OLLAMA_MODEL"
else
  log_ok "Modelo Ollama ya instalado: $OLLAMA_MODEL"
fi

curl -fsS "http://127.0.0.1:${OLLAMA_PORT}/v1/models" | grep -Fq "$OLLAMA_MODEL" || die "Ollama /v1/models no devuelve $OLLAMA_MODEL"

[[ -n "${DOGRAH_API_CONTAINER:-}" ]] || die "Falta DOGRAH_API_CONTAINER en .runtime/state.env. Ejecutá configure-dograh.sh primero."
[[ -n "${DOGRAH_DOCKER_GATEWAY:-}" ]] || die "Falta DOGRAH_DOCKER_GATEWAY en .runtime/state.env."
docker inspect "$DOGRAH_API_CONTAINER" >/dev/null 2>&1 || die "El contenedor Dograh API guardado ya no existe; reejecutá configure-dograh.sh"

docker exec -e OLLAMA_HOST_URL="http://${DOGRAH_DOCKER_GATEWAY}:${OLLAMA_PORT}" -e OLLAMA_MODEL="$OLLAMA_MODEL" "$DOGRAH_API_CONTAINER" python -c '
import json, os, urllib.request
base = os.environ["OLLAMA_HOST_URL"]
model = os.environ["OLLAMA_MODEL"]
with urllib.request.urlopen(base + "/v1/models", timeout=10) as r:
    data = json.load(r)
    assert r.status == 200
    assert model in [m.get("id") for m in data.get("data", [])]
payload = json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": "Respondé solamente: OLLAMA OK"}],
    "temperature": 0
}).encode()
req = urllib.request.Request(base + "/v1/chat/completions", data=payload,
                             headers={"Content-Type": "application/json"}, method="POST")
with urllib.request.urlopen(req, timeout=120) as r:
    data = json.load(r)
    content = data["choices"][0]["message"]["content"].strip()
    assert content
    print("Dograh -> Ollama OpenAI API: HTTP", r.status, "respuesta:", content[:80])
'

ps_output="$(ollama ps || true)"
if grep -F "$OLLAMA_MODEL" <<<"$ps_output" | grep -q '100% GPU'; then
  log_ok "Ollama: $OLLAMA_MODEL está 100% GPU"
elif grep -F "$OLLAMA_MODEL" <<<"$ps_output" | grep -q 'GPU'; then
  log_info "Ollama: uso mixto/GPUs detectado"
elif grep -F "$OLLAMA_MODEL" <<<"$ps_output" | grep -q 'CPU'; then
  log_warn "Ollama: modelo cargado en CPU"
else
  log_info "ollama ps no muestra el modelo cargado en este instante"
fi
log_ok "Ollama validado desde Dograh"
