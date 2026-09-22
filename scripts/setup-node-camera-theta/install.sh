#!/usr/bin/env bash
# install.sh — cài deps, build libuvc-theta + sample, cài udev/systemd/modprobe
# CHẠY TRÊN UBUNTU. Không chạy trên máy Windows hiện tại.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=theta.conf
source "${SCRIPT_DIR}/theta.conf"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: script này chỉ dành cho Ubuntu/Linux." >&2
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Chạy với sudo: sudo $0" >&2
  exit 1
fi

REAL_USER="${SUDO_USER:-root}"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"

echo "==> [1/6] Cài gói hệ thống"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  build-essential cmake pkg-config git \
  libusb-1.0-0-dev libjpeg-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
  gstreamer1.0-libav gstreamer1.0-tools \
  gstreamer1.0-vaapi vainfo \
  v4l2loopback-dkms v4l-utils \
  python3

echo "==> [2/6] Clone upstream vào ${THETA_PREFIX}"
mkdir -p "${THETA_PREFIX}"
if [[ ! -d "${LIBUVC_THETA_DIR}/.git" ]]; then
  git clone "${LIBUVC_THETA_REPO}" "${LIBUVC_THETA_DIR}"
else
  git -C "${LIBUVC_THETA_DIR}" pull --ff-only || true
fi
if [[ ! -d "${LIBUVC_THETA_SAMPLE_DIR}/.git" ]]; then
  git clone "${LIBUVC_THETA_SAMPLE_REPO}" "${LIBUVC_THETA_SAMPLE_DIR}"
else
  git -C "${LIBUVC_THETA_SAMPLE_DIR}" pull --ff-only || true
fi

echo "==> [3/6] Build & install libuvc-theta"
cmake -S "${LIBUVC_THETA_DIR}" -B "${LIBUVC_THETA_DIR}/build"
cmake --build "${LIBUVC_THETA_DIR}/build" -j"$(nproc)"
cmake --install "${LIBUVC_THETA_DIR}/build"
ldconfig

echo "==> [4/6] Patch sample (Theta X + loopback device) rồi build"
# apply-patches cần path đúng — chạy với user thường cũng được nhưng đang root
bash "${SCRIPT_DIR}/apply-patches.sh"
make -C "${LIBUVC_THETA_SAMPLE_DIR}/gst" clean || true
make -C "${LIBUVC_THETA_SAMPLE_DIR}/gst"
# gst_loopback là symlink tới gst_viewer
ln -sfn gst_viewer "${LIBUVC_THETA_SAMPLE_DIR}/gst/gst_loopback"
test -x "${GST_LOOPBACK_BIN}"

echo "==> [5/6] Cấu hình v4l2loopback cố định /dev/video${THETA_VIDEO_NR}"
install -d /etc/modprobe.d /etc/modules-load.d
cat > /etc/modprobe.d/v4l2loopback-theta.conf <<EOF
# Ricoh Theta X virtual capture node
options v4l2loopback exclusive_caps=1 video_nr=${THETA_VIDEO_NR} card_label=${THETA_CARD_LABEL}
EOF
cat > /etc/modules-load.d/v4l2loopback-theta.conf <<EOF
v4l2loopback
EOF

# Nạp ngay (có thể fail nếu module đang busy — bỏ qua)
modprobe -r v4l2loopback 2>/dev/null || true
modprobe v4l2loopback exclusive_caps=1 video_nr="${THETA_VIDEO_NR}" card_label="${THETA_CARD_LABEL}" || true

echo "==> [6/6] Cài udev + systemd"
install -m 0644 "${SCRIPT_DIR}/udev/99-theta-x.rules" /etc/udev/rules.d/99-theta-x.rules
install -m 0644 "${SCRIPT_DIR}/systemd/theta-loopback.service" /etc/systemd/system/theta-loopback.service
# Nhúng path tuyệt đối vào unit drop-in
install -d /etc/systemd/system/theta-loopback.service.d
cat > /etc/systemd/system/theta-loopback.service.d/override.conf <<EOF
[Service]
Environment=THETA_DAEMON=1
Environment=LD_LIBRARY_PATH=/usr/local/lib
EnvironmentFile=-${SCRIPT_DIR}/theta.conf
ExecStart=
ExecStart=${SCRIPT_DIR}/start-loopback.sh
EOF

# Copy scripts vào prefix để máy không phụ thuộc đường dẫn repo
install -d "${THETA_PREFIX}/bin"
install -m 0755 "${SCRIPT_DIR}/start-loopback.sh" "${THETA_PREFIX}/bin/start-loopback.sh"
install -m 0755 "${SCRIPT_DIR}/apply-patches.sh" "${THETA_PREFIX}/bin/apply-patches.sh"
install -m 0644 "${SCRIPT_DIR}/theta.conf" "${THETA_PREFIX}/bin/theta.conf"
# Sửa ExecStart dùng bản trong /opt
cat > /etc/systemd/system/theta-loopback.service.d/override.conf <<EOF
[Service]
Environment=THETA_DAEMON=1
Environment=LD_LIBRARY_PATH=/usr/local/lib
EnvironmentFile=-${THETA_PREFIX}/bin/theta.conf
ExecStart=
ExecStart=${THETA_PREFIX}/bin/start-loopback.sh
EOF

udevadm control --reload-rules
systemctl daemon-reload
systemctl enable theta-loopback.service

chown -R "${REAL_USER}:${REAL_USER}" "${THETA_PREFIX}" 2>/dev/null || true

echo
echo "OK. Kiểm tra:"
echo "  1) Bật LIVE trên Theta X, cắm USB"
echo "  2) lsusb | grep -i ricoh   # kỳ vọng idProduct ${THETA_USB_PID_LIVE}"
echo "  3) v4l2-ctl --list-devices # kỳ vọng ${THETA_CARD_LABEL} → /dev/video${THETA_VIDEO_NR}"
echo "  4) systemctl status theta-loopback"
echo "  5) Manual: ${THETA_PREFIX}/bin/start-loopback.sh"
echo "  6) Test:   gst-launch-1.0 v4l2src device=/dev/video${THETA_VIDEO_NR} ! videoconvert ! autovideosink sync=false"
