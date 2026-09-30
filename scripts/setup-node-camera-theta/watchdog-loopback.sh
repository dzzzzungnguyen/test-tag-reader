#!/usr/bin/env bash
# watchdog-loopback.sh — khi Theta LIVE mà loopback không đẩy frame → restart service.
# Chạy bởi theta-loopback-watchdog.timer (oneshot định kỳ).
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

: "${THETA_USB_VID:=05ca}"
: "${THETA_USB_PID_LIVE:=2717}"
: "${THETA_WATCHDOG_WARMUP_SEC:=12}"
: "${THETA_WATCHDOG_COOLDOWN_SEC:=45}"

STATE_DIR="${THETA_WATCHDOG_STATE_DIR:-/run/theta}"
STATE_FILE="${STATE_DIR}/last_restart"
CHECK_BIN="${SCRIPT_DIR}/check-stream.sh"
SERVICE="theta-loopback.service"

mkdir -p "${STATE_DIR}"

usb_live() {
  lsusb -d "${THETA_USB_VID}:${THETA_USB_PID_LIVE}" >/dev/null 2>&1
}

now_ts() {
  date +%s
}

age_since_restart() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    echo 999999
    return
  fi
  local last
  last="$(cat "${STATE_FILE}" 2>/dev/null || echo 0)"
  echo $(($(now_ts) - last))
}

mark_restart() {
  now_ts >"${STATE_FILE}"
}

if ! usb_live; then
  echo "watchdog: no LIVE USB ${THETA_USB_VID}:${THETA_USB_PID_LIVE} — skip"
  exit 0
fi

if ! systemctl is-active --quiet "${SERVICE}"; then
  echo "watchdog: LIVE USB present but ${SERVICE} inactive — starting"
  systemctl start "${SERVICE}" || true
  mark_restart
  exit 0
fi

age="$(age_since_restart)"
if ((age < THETA_WATCHDOG_WARMUP_SEC)); then
  echo "watchdog: warmup ${age}s/${THETA_WATCHDOG_WARMUP_SEC}s after restart — skip check"
  exit 0
fi

if "${CHECK_BIN}"; then
  exit 0
fi

if ((age < THETA_WATCHDOG_COOLDOWN_SEC)); then
  echo "watchdog: stream fail but cooldown ${age}s/${THETA_WATCHDOG_COOLDOWN_SEC}s — skip restart"
  exit 0
fi

echo "watchdog: stream stalled while LIVE — restarting ${SERVICE}"
systemctl restart "${SERVICE}"
mark_restart
exit 0
