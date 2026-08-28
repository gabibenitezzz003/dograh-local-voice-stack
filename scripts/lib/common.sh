#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RUNTIME_DIR="${RUNTIME_DIR:-$PROJECT_ROOT/.runtime}"

log_info() { printf '[INFO] %s\n' "$*"; }
log_ok()   { printf '[OK]   %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
die()      { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Falta el comando requerido: $1"
}

retry() {
  local attempts="$1" delay="$2"
  shift 2
  local n=1
  until "$@"; do
    if (( n >= attempts )); then
      return 1
    fi
    sleep "$delay"
    n=$((n + 1))
  done
}

ensure_runtime_dirs() {
  mkdir -p "$RUNTIME_DIR" "$RUNTIME_DIR/backups"
  chmod 700 "$RUNTIME_DIR"
}

backup_file() {
  local source="$1"
  [[ -e "$source" ]] || return 0
  ensure_runtime_dirs
  local stamp slug target_dir
  stamp="$(date +%Y%m%d-%H%M%S)"
  slug="${source#/}"
  slug="${slug//\//__}"
  target_dir="$RUNTIME_DIR/backups/$stamp"
  mkdir -p "$target_dir"
  cp -a "$source" "$target_dir/$slug"
  log_info "Backup: $source -> $target_dir/$slug"
}

load_project_env() {
  local env_file
  for env_file in "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env" "$RUNTIME_DIR/state.env" "$RUNTIME_DIR/secrets.env"; do
    if [[ -f "$env_file" ]]; then
      set -a
      source "$env_file"
      set +a
    fi
  done
}

write_env_value() {
  local file="$1" key="$2" value="$3"
  ensure_runtime_dirs
  touch "$file"
  chmod 600 "$file"
  if grep -qE "^${key}=" "$file"; then
    local tmp
    tmp="$(mktemp)"
    awk -v k="$key" -v v="$value" 'BEGIN{FS=OFS="="} $1==k {$0=k OFS v} {print}' "$file" > "$tmp"
    mv "$tmp" "$file"
    chmod 600 "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}
