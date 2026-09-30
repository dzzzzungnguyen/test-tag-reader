#!/usr/bin/env bash
# check-stream.sh — xác nhận /dev/videoN đang có frame thật (không chỉ node tồn tại).
# Exit 0 = OK, 1 = không nhận đủ buffer trong timeout, 2 = thiếu device / gst.
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
: "${THETA_STREAM_CHECK_TIMEOUT:=5}"
: "${THETA_STREAM_CHECK_BUFFERS:=5}"

VIDEO_DEV="/dev/video${THETA_VIDEO_NR}"

if [[ ! -e "${VIDEO_DEV}" ]]; then
  echo "STREAM FAIL: missing ${VIDEO_DEV}" >&2
  exit 2
fi

if ! command -v gst-launch-1.0 >/dev/null 2>&1; then
  echo "STREAM FAIL: gst-launch-1.0 not found" >&2
  exit 2
fi

if ! command -v timeout >/dev/null 2>&1; then
  echo "STREAM FAIL: timeout not found" >&2
  exit 2
fi

# num-buffers=N → EOS và thoát 0 nếu có frame. Không có frame → treo → timeout 124.
set +e
out="$(timeout "${THETA_STREAM_CHECK_TIMEOUT}" gst-launch-1.0 -q \
  v4l2src device="${VIDEO_DEV}" num-buffers="${THETA_STREAM_CHECK_BUFFERS}" \
  ! fakesink sync=false 2>&1)"
rc=$?
set -e

if [[ "${rc}" -eq 0 ]]; then
  echo "STREAM OK ${VIDEO_DEV} (${THETA_STREAM_CHECK_BUFFERS} buffers ≤${THETA_STREAM_CHECK_TIMEOUT}s)"
  exit 0
fi

echo "STREAM FAIL ${VIDEO_DEV} rc=${rc} (timeout/no frames — gst_loopback có thể treo idle)" >&2
if [[ -n "${out}" ]]; then
  echo "${out}" >&2
fi
exit 1
