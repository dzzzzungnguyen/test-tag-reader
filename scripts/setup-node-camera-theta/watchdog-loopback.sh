#!/usr/bin/env bash
# watchdog-loopback.sh — Theta LIVE mà gst_loopback gần như không tốn CPU → restart.
# Không mở /dev/videoN (exclusive_caps: opener thứ hai làm hỏng client đang đọc).
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
: "${THETA_WATCHDOG_SAMPLE_SEC:=2}"
: "${THETA_WATCHDOG_CPU_MIN:=8}"

STATE_DIR="${THETA_WATCHDOG_STATE_DIR:-/run/theta}"
STATE_FILE="${STATE_DIR}/last_restart"
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

# %CPU trong một cửa sổ ngắn. ps %cpu là trung bình từ lúc process start — không dùng được
# để bắt stall sau một lúc chạy khỏe. Không mở /dev/videoN: exclusive_caps=1, opener thứ hai
# làm check-stream fail và restart nhầm stream đang có client (bench).
sample_cpu_percent() {
  local pid="$1"
  local hz t1 t2
  hz="$(getconf CLK_TCK)"
  if [[ ! -r "/proc/${pid}/stat" ]]; then
    echo -1
    return
  fi
  t1="$(awk '{print $14+$15}' "/proc/${pid}/stat")"
  sleep "${THETA_WATCHDOG_SAMPLE_SEC}"
  if [[ ! -r "/proc/${pid}/stat" ]]; then
    echo -1
    return
  fi
  t2="$(awk '{print $14+$15}' "/proc/${pid}/stat")"
  echo $(( (t2 - t1) * 100 / hz / THETA_WATCHDOG_SAMPLE_SEC ))
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

pid="$(systemctl show -p MainPID --value "${SERVICE}")"
cpu="$(sample_cpu_percent "${pid}")"
if [[ "${cpu}" -lt 0 ]]; then
  echo "watchdog: cannot sample MainPID=${pid} — skip"
  exit 0
fi
if ((cpu >= THETA_WATCHDOG_CPU_MIN)); then
  echo "watchdog: gst_loopback pid=${pid} cpu=${cpu}% ≥${THETA_WATCHDOG_CPU_MIN}% — alive"
  exit 0
fi

if ((age < THETA_WATCHDOG_COOLDOWN_SEC)); then
  echo "watchdog: cpu=${cpu}% idle but cooldown ${age}s/${THETA_WATCHDOG_COOLDOWN_SEC}s — skip restart"
  exit 0
fi

echo "watchdog: gst_loopback pid=${pid} cpu=${cpu}% <${THETA_WATCHDOG_CPU_MIN}% while LIVE — restarting ${SERVICE}"
systemctl restart "${SERVICE}"
mark_restart
exit 0
