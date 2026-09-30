#!/usr/bin/env bash
# status.sh — kiểm tra Theta LIVE + loopback + frame thật + service/watchdog (Ubuntu)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=theta.conf
source "${SCRIPT_DIR}/theta.conf"

VIDEO_DEV="/dev/video${THETA_VIDEO_NR}"
CHECK_BIN="${SCRIPT_DIR}/check-stream.sh"

echo "=== USB Ricoh ==="
lsusb -d "${THETA_USB_VID}:" || true
if lsusb -d "${THETA_USB_VID}:${THETA_USB_PID_LIVE}" >/dev/null 2>&1; then
  echo "LIVE OK (${THETA_USB_VID}:${THETA_USB_PID_LIVE})"
elif lsusb -d "${THETA_USB_VID}:0373" >/dev/null 2>&1; then
  echo "CHƯA LIVE — đang ở camera mode 05ca:0373"
  echo "         Bật live streaming trên Theta X tới khi lsusb ra ${THETA_USB_VID}:${THETA_USB_PID_LIVE}"
else
  echo "CHƯA thấy Theta / chưa LIVE (PID kỳ vọng ${THETA_USB_PID_LIVE})"
fi

echo
echo "=== V4L2 devices ==="
echo "Target: ${VIDEO_DEV} label=${THETA_CARD_LABEL}"
if [[ -e "${VIDEO_DEV}" ]]; then
  echo "EXISTS ${VIDEO_DEV}"
  v4l2-ctl -d "${VIDEO_DEV}" --info 2>&1 || true
else
  echo "MISSING ${VIDEO_DEV}"
fi

echo
echo "=== Stream (frame thật) ==="
if [[ -x "${CHECK_BIN}" ]]; then
  set +e
  "${CHECK_BIN}"
  stream_rc=$?
  set -e
  if [[ "${stream_rc}" -ne 0 ]]; then
    echo "→ Node có thể tồn tại nhưng gst_loopback treo idle."
    echo "  Thử: sudo systemctl restart theta-loopback"
  fi
else
  echo "MISSING ${CHECK_BIN} — chạy sudo ./install-units.sh"
fi

echo
echo "=== gst_loopback binary ==="
if [[ -x "${GST_LOOPBACK_BIN}" ]]; then
  echo "OK ${GST_LOOPBACK_BIN}"
  ls -l "${LIBUVC_THETA_SAMPLE_DIR}/gst/gst_viewer" "${GST_LOOPBACK_BIN}" 2>/dev/null || true
  if pgrep -n gst_loopback >/dev/null 2>&1; then
    ps -p "$(pgrep -n gst_loopback)" -o pid,etime,%cpu,rss,cmd
  else
    echo "gst_loopback process: not running"
  fi
else
  echo "MISSING ${GST_LOOPBACK_BIN} — chạy sudo ./install.sh"
fi

echo
echo "=== systemd ==="
systemctl is-enabled theta-loopback.service 2>/dev/null || echo "theta-loopback: not enabled"
systemctl --no-pager -l status theta-loopback.service 2>/dev/null || true
echo
systemctl is-enabled theta-loopback-watchdog.timer 2>/dev/null || echo "watchdog timer: not enabled"
systemctl --no-pager -l status theta-loopback-watchdog.timer 2>/dev/null || true
