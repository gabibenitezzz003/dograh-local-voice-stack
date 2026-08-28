#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }
assert_file() { [[ -f "$ROOT/$1" ]] && pass "$1 existe" || fail "$1 falta"; }
assert_grep() { grep -Eq "$2" "$ROOT/$1" && pass "$1 contiene $2" || fail "$1 no contiene $2"; }
assert_not_grep() { ! grep -Eq "$2" "$ROOT/$1" && pass "$1 excluye $2" || fail "$1 contiene inesperadamente $2"; }

for f in README.md LICENSE .gitignore .env.example; do assert_file "$f"; done
assert_grep .gitignore '^\.runtime/$'
assert_grep .gitignore '^\.env$'
assert_not_grep .env.example '(^|_)(PASSWORD|SECRET|TOKEN|API_KEY)=[^<${[:space:]][^[:space:]]{7,}'

(( failures == 0 ))

# Tarea 2
for f in scripts/lib/common.sh scripts/detect-system.sh; do assert_file "$f"; done
if [[ -f "$ROOT/scripts/lib/common.sh" ]]; then
  assert_grep scripts/lib/common.sh '^set -euo pipefail$'
fi
if [[ -f "$ROOT/scripts/detect-system.sh" ]]; then
  assert_grep scripts/detect-system.sh '^set -euo pipefail$'
  detector_output="$(bash "$ROOT/scripts/detect-system.sh" --env 2>/dev/null || true)"
  for key in OS_FAMILY OS_ID LAN_IP LAN_CIDR FIREWALL DOCKER_AVAILABLE NVIDIA_AVAILABLE; do
    grep -Eq "^${key}=" <<<"$detector_output" && pass "detect-system expone $key" || fail "detect-system no expone $key"
  done
fi

(( failures == 0 ))

# Tarea 3
for f in \
  config/asterisk/http.conf.template \
  config/asterisk/ari.conf.template \
  config/asterisk/pjsip.conf.template \
  config/asterisk/extensions.conf.template \
  config/asterisk/websocket_client.conf.template \
  scripts/configure-asterisk.sh; do
  assert_file "$f"
done
if [[ -f "$ROOT/config/asterisk/pjsip.conf.template" ]]; then
  assert_grep config/asterisk/pjsip.conf.template '^\[transport-udp\]$'
  assert_grep config/asterisk/pjsip.conf.template '^\[transport-tcp\]$'
  assert_grep config/asterisk/pjsip.conf.template 'pass(word)=\{\{SIP_PASSWORD\}\}'
  assert_not_grep config/asterisk/pjsip.conf.template 'pass(word)=[A-Za-z0-9]{12,}$'
fi
if [[ -f "$ROOT/config/asterisk/ari.conf.template" ]]; then
  assert_grep config/asterisk/ari.conf.template '^\[dograh\]$'
  assert_grep config/asterisk/ari.conf.template '^read_only=no$'
fi
if [[ -f "$ROOT/config/asterisk/websocket_client.conf.template" ]]; then
  assert_grep config/asterisk/websocket_client.conf.template 'connection_type[[:space:]]*=[[:space:]]*per_call_config'
  assert_grep config/asterisk/websocket_client.conf.template '/api/v1/telephony/ws/ari'
fi
if [[ -f "$ROOT/scripts/configure-asterisk.sh" ]]; then
  assert_grep scripts/configure-asterisk.sh 'BEGIN DOGRAH-LOCAL-VOICE-STACK'
  assert_grep scripts/configure-asterisk.sh 'backup_file'
  assert_grep scripts/configure-asterisk.sh '\-\-render-only'
fi

(( failures == 0 ))

# Tarea 4
for f in scripts/install-arch.sh scripts/install-debian.sh tests/test-install-arch-dry-run.sh; do assert_file "$f"; done
if [[ -f "$ROOT/scripts/install-arch.sh" ]]; then
  assert_grep scripts/install-arch.sh '^set -euo pipefail$'
  assert_grep scripts/install-arch.sh 'pacman -Si asterisk'
  assert_grep scripts/install-arch.sh '\-\-dry-run'
fi
if [[ -f "$ROOT/scripts/install-debian.sh" ]]; then
  assert_grep scripts/install-debian.sh '^set -euo pipefail$'
  assert_grep scripts/install-debian.sh 'apt-get update'
  assert_grep scripts/install-debian.sh '\-\-dry-run'
fi
if [[ -f "$ROOT/tests/test-install-arch-dry-run.sh" ]]; then
  bash "$ROOT/tests/test-install-arch-dry-run.sh" || fail "regresión install-arch --dry-run"
fi

(( failures == 0 ))

# Tarea 5
for f in scripts/configure-dograh.sh config/dograh/.env.example config/dograh/docker-compose.override.yml; do assert_file "$f"; done
if [[ -f "$ROOT/config/dograh/docker-compose.override.yml" ]]; then
  assert_grep config/dograh/docker-compose.override.yml '^services:'
  assert_grep config/dograh/docker-compose.override.yml '^[[:space:]]+api:'
  assert_grep config/dograh/docker-compose.override.yml 'external:[[:space:]]+true'
  assert_not_grep config/dograh/docker-compose.override.yml 'n8n'
fi
if [[ -f "$ROOT/scripts/configure-dograh.sh" ]]; then
  assert_grep scripts/configure-dograh.sh 'dograh-hq/dograh.git'
  assert_grep scripts/configure-dograh.sh 'start_docker.sh'
  assert_grep scripts/configure-dograh.sh 'ENABLE_TELEMETRY'
  assert_grep scripts/configure-dograh.sh '/api/v1/health'
  assert_grep scripts/configure-dograh.sh 'compose ps -q api'
fi

(( failures == 0 ))

# Tarea 6
assert_file scripts/configure-firewall.sh
if [[ -f "$ROOT/scripts/configure-firewall.sh" ]]; then
  assert_grep scripts/configure-firewall.sh 'DOGRAH_DOCKER_SUBNET'
  assert_grep scripts/configure-firewall.sh 'RTP_START.*RTP_END'
  assert_not_grep scripts/configure-firewall.sh 'ufw allow 8088'
  assert_not_grep scripts/configure-firewall.sh 'ufw allow 11434'
  assert_grep scripts/configure-firewall.sh 'from.*DOGRAH_DOCKER_SUBNET.*ARI_PORT'
  assert_grep scripts/configure-firewall.sh 'from.*DOGRAH_DOCKER_SUBNET.*OLLAMA_PORT'
fi

(( failures == 0 ))

# Tarea 7
for f in config/ollama/override.conf scripts/configure-ollama.sh; do assert_file "$f"; done
if [[ -f "$ROOT/config/ollama/override.conf" ]]; then
  assert_grep config/ollama/override.conf 'OLLAMA_HOST=0\.0\.0\.0:11434'
fi
if [[ -f "$ROOT/scripts/configure-ollama.sh" ]]; then
  assert_grep scripts/configure-ollama.sh '/v1/models'
  assert_grep scripts/configure-ollama.sh '/v1/chat/completions'
  assert_grep scripts/configure-ollama.sh 'ollama ps'
  assert_not_grep scripts/configure-ollama.sh 'nvidia-container-toolkit'
fi

(( failures == 0 ))

# Tarea 8
for f in scripts/verify-stack.sh scripts/doctor.sh; do assert_file "$f"; done
if [[ -f "$ROOT/scripts/verify-stack.sh" ]]; then
  for check_id in \
    system.os system.docker asterisk.service asterisk.sip_udp asterisk.sip_tcp \
    asterisk.ari_http asterisk.ari_auth asterisk.websocket_modules \
    sip.endpoint_2001 sip.echo_600 dograh.api_health dograh.ari_manager \
    dograh.ari_websocket ollama.api ollama.model ollama.from_dograh \
    firewall.sip firewall.rtp firewall.ari firewall.ollama docker.dns_collision; do
    grep -Fq "$check_id" "$ROOT/scripts/verify-stack.sh" && pass "verify-stack define $check_id" || fail "verify-stack no define $check_id"
  done
  assert_grep scripts/verify-stack.sh '\-\-json'
  assert_grep scripts/verify-stack.sh 'curl.*-u.*dograh.*ARI_PASSWORD'
fi
if [[ -f "$ROOT/scripts/doctor.sh" ]]; then
  assert_grep scripts/doctor.sh 'Solución|SOLUCION|solución'
  assert_not_grep scripts/doctor.sh 'probá reiniciando'
fi

(( failures == 0 ))

# Tarea 9
assert_file scripts/install.sh
if [[ -f "$ROOT/scripts/install.sh" ]]; then
  assert_grep scripts/install.sh '^set -euo pipefail$'
  assert_grep scripts/install.sh 'PHASES=.*preflight.*platform.*asterisk.*sip_checkpoint.*network.*firewall.*dograh.*ari_checkpoint.*ollama.*final_verify'
  assert_grep scripts/install.sh '\-\-resume'
  assert_grep scripts/install.sh '\-\-dry-run'
  assert_grep scripts/install.sh 'Use SIP endpoint instead'
  assert_grep scripts/install.sh '600'
  assert_grep scripts/install.sh '2001'
fi

(( failures == 0 ))

# Tarea 10
for f in tests/smoke-test.sh scripts/uninstall.sh; do assert_file "$f"; done
if [[ -f "$ROOT/tests/smoke-test.sh" ]]; then
  assert_grep tests/smoke-test.sh '/v1/chat/completions'
  assert_grep tests/smoke-test.sh 'pjsip show endpoint|verify-stack'
  assert_grep tests/smoke-test.sh 'Echo|echo_600|dialplan'
  assert_not_grep tests/smoke-test.sh 'audio.*PASS|PASS.*audio'
fi
if [[ -f "$ROOT/scripts/uninstall.sh" ]]; then
  assert_grep scripts/uninstall.sh '\-\-yes'
  assert_grep scripts/uninstall.sh 'BEGIN DOGRAH-LOCAL-VOICE-STACK'
  assert_not_grep scripts/uninstall.sh 'rm[[:space:]]+-f[[:space:]]+/etc/asterisk/.*\.conf'
  assert_grep scripts/uninstall.sh 'FIREWALL_RULE_.*_ADDED'
fi

(( failures == 0 ))

# Tarea 11
for f in \
  docs/ARCH-CACHYOS.md docs/UBUNTU-DEBIAN.md docs/DOGRAH.md docs/ASTERISK.md \
  docs/LINPHONE.md docs/OLLAMA.md docs/FIREWALL.md docs/TROUBLESHOOTING.md \
  docs/SECURITY.md docs/HOW-IT-WORKS.md; do
  assert_file "$f"
done

if [[ -f "$ROOT/README.md" ]]; then
  assert_grep README.md 'Linphone.*600|600.*Linphone'
  assert_grep README.md 'Asterisk Local'
  assert_grep README.md 'Use SIP endpoint instead'
  assert_grep README.md '2001'
  assert_grep README.md 'qwen2\.5:7b-instruct-q5_K_M'
  assert_grep README.md 'Resultado esperado'
fi

if [[ -f "$ROOT/docs/TROUBLESHOOTING.md" ]]; then
  for incident in \
    'Protocol not supported \[93\]' \
    '401 Unauthorized' \
    'No objects found' \
    'ARI.*[Tt]imeout|Timeout.*ARI' \
    'UFW.*Docker|Docker.*UFW' \
    'Backend connection failed' \
    '127\.0\.0\.1:11434|127\.0\.0\.1.*Ollama' \
    'postgres' \
    'Asterisk.*timeout|timeout.*Asterisk' \
    'Linphone.*Unauthorized|Unauthorized.*Linphone' \
    'RTP|sin audio' \
    'Caller ID.*SIP endpoint|SIP endpoint.*Caller ID' \
    'Baresip.*127\.0\.0\.1|127\.0\.0\.1.*Baresip'; do
    assert_grep docs/TROUBLESHOOTING.md "$incident"
  done
  for heading in '^### Síntoma$' '^### Causa$' '^### Diagnóstico$' '^### Solución$' '^### Verificación$'; do
    assert_grep docs/TROUBLESHOOTING.md "$heading"
  done
fi

if [[ -f "$ROOT/docs/SECURITY.md" ]]; then
  assert_grep docs/SECURITY.md '8088'
  assert_grep docs/SECURITY.md '11434'
  assert_grep docs/SECURITY.md 'Pedro'
  assert_grep docs/SECURITY.md 'PSTN|trunk|carrier|gateway'
fi

(( failures == 0 ))
