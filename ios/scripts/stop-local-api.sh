#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/.logs"

stop_pidfile() {
  local name="$1"
  local pidfile="$LOG_DIR/$name.pid"
  if [[ ! -f "$pidfile" ]]; then
    return
  fi

  local pid
  pid="$(cat "$pidfile")"
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid"
    for _ in {1..10}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done
  fi
  rm -f "$pidfile"
  printf 'Stopped %s (PID %s)\n' "$name" "$pid"
}

stop_pidfile api
stop_pidfile mock-oauth
stop_pidfile moto

if [[ -f "$LOG_DIR/.started-opensearch" ]]; then
  brew services stop opensearch
  rm -f "$LOG_DIR/.started-opensearch"
fi
if [[ -f "$LOG_DIR/.started-postgresql" ]]; then
  brew services stop postgresql@17
  rm -f "$LOG_DIR/.started-postgresql"
fi
