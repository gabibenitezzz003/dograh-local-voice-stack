#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
load_project_env
: "${SIP_EXTENSION:=2001}"
: "${ECHO_EXTENSION:=600}"
: "${OLLAMA_PORT:=11434}"
: "${OLLAMA_MODEL:=qwen2.5:7b-instruct-q5_K_M}"

fail() { printf '[SMOKE FAIL] %s\n' "$*" >&2; exit 1; }
ok() { printf '[SMOKE OK] %s\n' "$*"; }

"$ROOT/scripts/verify-stack.sh" --tsv >/tmp/dograh-local-voice-stack-verify.tsv || {
  cat /tmp/dograh-local-voice-stack-verify.tsv >&2 || true
  fail "verify-stack reportó checks críticos fallidos"
}
ok "verify-stack sin FAIL"

asterisk -rx "pjsip show endpoint ${SIP_EXTENSION}" | grep -q "Endpoint:.*${SIP_EXTENSION}" || fail "Falta endpoint ${SIP_EXTENSION}"
ok "PJSIP endpoint ${SIP_EXTENSION}"
asterisk -rx "dialplan show ${ECHO_EXTENSION}@from-internal" | grep -q "$ECHO_EXTENSION" || fail "Falta Echo() ${ECHO_EXTENSION}"
ok "Dialplan Echo() ${ECHO_EXTENSION}"

[[ -n "${DOGRAH_API_CONTAINER:-}" && -n "${DOGRAH_DOCKER_GATEWAY:-}" ]] || fail "Falta estado de Dograh/gateway"
docker exec -e BASE="http://${DOGRAH_DOCKER_GATEWAY}:${OLLAMA_PORT}" -e MODEL="$OLLAMA_MODEL" "$DOGRAH_API_CONTAINER" python -c '
import json, os, urllib.request
payload=json.dumps({
  "model":os.environ["MODEL"],
  "messages":[{"role":"user","content":"Respondé solamente: SMOKE OK"}],
  "temperature":0
}).encode()
req=urllib.request.Request(os.environ["BASE"]+"/v1/chat/completions",data=payload,
    headers={"Content-Type":"application/json"},method="POST")
with urllib.request.urlopen(req,timeout=120) as r:
    data=json.load(r)
    assert r.status==200
    assert data["choices"][0]["message"]["content"].strip()
' || fail "Dograh no pudo completar contra Ollama"
ok "Dograh → Ollama /v1/chat/completions"

echo "Smoke automático completo. IMPORTANTE: este script NO declara que el audio humano pasó. Confirmá manualmente Linphone→600 y Dograh Test Call→2001."
