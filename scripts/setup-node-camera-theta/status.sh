#!/usr/bin/env bash
# status.sh — kiểm tra nhanh Theta LIVE + loopback + service (Ubuntu)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=theta.conf
source "${SCRIPT_DIR}/theta.conf"

VIDEO_DEV="/dev/video${THETA_VIDEO_NR}"

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
v4l2-ctl --list-devices 2>/dev/null || echo "(v4l2-ctl thiếu)"
echo "Target: ${VIDEO_DEV} label=${THETA_CARD_LABEL}"
[[ -e "${VIDEO_DEV}" ]] && echo "EXISTS ${VIDEO_DEV}" || echo "MISSING ${VIDEO_DEV}"

echo
echo "=== gst_loopback binary ==="
if [[ -x "${GST_LOOPBACK_BIN}" ]]; then
  echo "OK ${GST_LOOPBACK_BIN}"
  ls -l "${LIBUVC_THETA_SAMPLE_DIR}/gst/gst_viewer" "${GST_LOOPBACK_BIN}" 2>/dev/null || true
else
  echo "MISSING ${GST_LOOPBACK_BIN} — chạy sudo ./install.sh"
fi

echo
echo "=== systemd ==="
systemctl is-enabled theta-loopback.service 2>/dev/null || echo "not enabled"
systemctl --no-pager -l status theta-loopback.service 2>/dev/null || true
