#!/usr/bin/env bash
# start-loopback.sh — nạp v4l2loopback (nếu cần) rồi chạy gst_loopback
# Dùng tay hoặc bởi systemd (theta-loopback.service)
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

: "${THETA_VIDEO_NR:=1}"
: "${THETA_CARD_LABEL:=ThetaX}"
: "${GST_LOOPBACK_BIN:=/opt/theta/libuvc-theta-sample/gst/gst_loopback}"
: "${THETA_DAEMON:=1}"

VIDEO_DEV="/dev/video${THETA_VIDEO_NR}"
export THETA_DAEMON
export LD_LIBRARY_PATH="/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

ensure_loopback() {
  if [[ -e "${VIDEO_DEV}" ]]; then
    # Xác nhận là loopback của ta (best-effort)
    return 0
  fi
  echo "Loading v4l2loopback → ${VIDEO_DEV} (${THETA_CARD_LABEL})"
  if [[ "${EUID}" -eq 0 ]]; then
    modprobe v4l2loopback exclusive_caps=1 \
      video_nr="${THETA_VIDEO_NR}" card_label="${THETA_CARD_LABEL}"
  else
    sudo modprobe v4l2loopback exclusive_caps=1 \
      video_nr="${THETA_VIDEO_NR}" card_label="${THETA_CARD_LABEL}"
  fi
  # Đợi node xuất hiện
  for _ in $(seq 1 50); do
    [[ -e "${VIDEO_DEV}" ]] && break
    sleep 0.1
  done
  if [[ ! -e "${VIDEO_DEV}" ]]; then
    echo "ERROR: ${VIDEO_DEV} không tồn tại sau modprobe" >&2
    v4l2-ctl --list-devices || true
    exit 1
  fi
}

wait_theta_usb() {
  local vid="${THETA_USB_VID:-05ca}"
  local pid="${THETA_USB_PID_LIVE:-2717}"
  echo "Waiting for Theta live USB ${vid}:${pid} ..."
  for _ in $(seq 1 100); do
    if lsusb -d "${vid}:${pid}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  echo "WARN: chưa thấy USB ${vid}:${pid} — vẫn thử gst_loopback (camera phải ở LIVE)" >&2
}

if [[ ! -x "${GST_LOOPBACK_BIN}" ]]; then
  echo "ERROR: không có executable ${GST_LOOPBACK_BIN}" >&2
  echo "Chạy install.sh trên Ubuntu trước." >&2
  exit 1
fi

ensure_loopback
wait_theta_usb

echo "Starting ${GST_LOOPBACK_BIN} → ${VIDEO_DEV}"
# stdin đóng: keywait đã được vá khi THETA_DAEMON=1
exec "${GST_LOOPBACK_BIN}"
