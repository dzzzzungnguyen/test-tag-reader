#!/usr/bin/env bash
# wait-stream-ready.sh — ExecStartPost: đợi warmup rồi kiểm tra frame.
# Fail → systemd coi unit failed → Restart=on-failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${SCRIPT_DIR}/theta.conf"
if [[ -f "${CONF}" ]]; then
  # shellcheck source=theta.conf
  set -a
  # shellcheck disable=SC1090
  source "${CONF}"
  set +a
fi

: "${THETA_STREAM_WARMUP_SEC:=12}"
STATE_DIR="${THETA_WATCHDOG_STATE_DIR:-/run/theta}"
mkdir -p "${STATE_DIR}"
# Đồng bộ với watchdog: tránh check/restart chồng ngay sau start
date +%s >"${STATE_DIR}/last_restart"

echo "wait-stream-ready: warmup ${THETA_STREAM_WARMUP_SEC}s ..."
sleep "${THETA_STREAM_WARMUP_SEC}"
exec "${SCRIPT_DIR}/check-stream.sh"
