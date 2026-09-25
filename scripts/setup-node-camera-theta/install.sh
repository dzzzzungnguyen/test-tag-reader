#!/usr/bin/env bash
# install.sh — cài deps, DKMS v4l2loopback (tag ghim), build libuvc-theta, udev/systemd
# CHẠY TRÊN UBUNTU. Không chạy trên máy Windows hiện tại.
# Không cài gói apt v4l2loopback-dkms (0.12.7 không build trên kernel >= 6.18).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=theta.conf
source "${SCRIPT_DIR}/theta.conf"

LOG=/var/log/theta-setup.log

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: script này chỉ dành cho Ubuntu/Linux." >&2
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Chạy với sudo: sudo $0" >&2
  exit 1
fi

REAL_USER="${SUDO_USER:-root}"

touch "${LOG}"
chmod 644 "${LOG}"
exec > >(tee -a "${LOG}") 2>&1

dump_fail_context() {
  set +e
  local krel build newest f
  krel="$(uname -r)"
  build="/lib/modules/${krel}/build"
  echo "kernel: ${krel}"
  if [[ -d "${build}" ]]; then
    echo "headers: ${build}"
  else
    echo "headers: KHÔNG có ${build}"
  fi
  echo "--- dkms status ---"
  dkms status || true
  echo "--- make.log (80 dòng cuối) ---"
  local -a logs=()
  shopt -s nullglob
  logs=(/var/lib/dkms/v4l2loopback/*/build/make.log)
  shopt -u nullglob
  newest=""
  for f in "${logs[@]}"; do
    if [[ -z "${newest}" || "${f}" -nt "${newest}" ]]; then
      newest="${f}"
    fi
  done
  if [[ -n "${newest}" ]]; then
    echo "file: ${newest}"
    tail -n 80 "${newest}" || true
  else
    echo "(không có make.log)"
  fi
  echo "Full log: ${LOG}"
}

on_err() {
  local line="$1"
  local rc="$2"
  echo "ERROR: install.sh dừng ở dòng ${line} (exit ${rc})"
  dump_fail_context
  exit "${rc}"
}

fail() {
  echo "ERROR: $*"
  dump_fail_context
  exit 1
}

trap 'on_err "$LINENO" "$?"' ERR

echo
echo "===== $(date -Is) install.sh pid=$$ kernel=$(uname -r) ====="

remove_other_loopback_dkms() {
  local line modver
  local -A seen=()
  if ! command -v dkms >/dev/null 2>&1; then
    return 0
  fi
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    modver="${line%%,*}"
    modver="${modver%%:*}"
    modver="${modver#v4l2loopback/}"
    modver="${modver// /}"
    [[ -z "${modver}" || "${modver}" == "${V4L2LOOPBACK_VERSION}" ]] && continue
    if [[ -n "${seen[${modver}]:-}" ]]; then
      continue
    fi
    seen["${modver}"]=1
    echo "Gỡ DKMS v4l2loopback/${modver}"
    dkms remove -m v4l2loopback -v "${modver}" --all
  done < <(dkms status -m v4l2loopback 2>/dev/null || true)
}

echo "==> [1/7] Gỡ gói Ubuntu v4l2loopback-dkms (nếu có) và hold"
export DEBIAN_FRONTEND=noninteractive
pkg_status="$(dpkg-query -W -f='${db:Status-Status}' v4l2loopback-dkms 2>/dev/null || true)"
if [[ -n "${pkg_status}" && "${pkg_status}" != "not-installed" ]]; then
  apt-get remove -y v4l2loopback-dkms
fi
# Hold có chủ đích: apt upgrade không được kéo 0.12.7 về và làm hỏng header.
echo "apt-mark hold v4l2loopback-dkms: cố ý. Gói Ubuntu 0.12.7 không build trên kernel >= 6.18."
echo "Gỡ hold chỉ khi apt-cache policy ra bản khác 0.12.7 và đã có vá kernel >= 6.18."
apt-mark hold v4l2loopback-dkms
modprobe -r v4l2loopback 2>/dev/null || true
remove_other_loopback_dkms

echo "==> [2/7] Cài gói hệ thống và kernel headers"
krel="$(uname -r)"
apt-get update
apt-get install -y \
  build-essential cmake pkg-config git \
  libusb-1.0-0-dev libjpeg-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
  gstreamer1.0-libav gstreamer1.0-tools \
  gstreamer1.0-vaapi vainfo \
  dkms v4l-utils \
  "linux-headers-${krel}" \
  linux-headers-generic-hwe-24.04 \
  python3

if [[ ! -d "/lib/modules/${krel}/build" ]]; then
  fail "không có /lib/modules/${krel}/build sau khi cài header. Dừng, không clone tiếp."
fi

echo "==> [3/7] DKMS v4l2loopback ${V4L2LOOPBACK_REF} cho ${krel}"
mkdir -p "${THETA_PREFIX}"
if [[ -d "${V4L2LOOPBACK_DIR}" && ! -d "${V4L2LOOPBACK_DIR}/.git" ]]; then
  fail "${V4L2LOOPBACK_DIR} tồn tại nhưng không phải git repo"
fi
if [[ ! -d "${V4L2LOOPBACK_DIR}/.git" ]]; then
  git clone --branch "${V4L2LOOPBACK_REF}" --depth 1 \
    "${V4L2LOOPBACK_REPO}" "${V4L2LOOPBACK_DIR}"
else
  head_tag="$(git -C "${V4L2LOOPBACK_DIR}" describe --tags --exact-match HEAD 2>/dev/null || true)"
  if [[ "${head_tag}" != "${V4L2LOOPBACK_REF}" ]]; then
    git -C "${V4L2LOOPBACK_DIR}" fetch --depth 1 origin \
      "refs/tags/${V4L2LOOPBACK_REF}:refs/tags/${V4L2LOOPBACK_REF}"
    git -C "${V4L2LOOPBACK_DIR}" checkout --detach "${V4L2LOOPBACK_REF}"
  fi
fi
head_tag="$(git -C "${V4L2LOOPBACK_DIR}" describe --tags --exact-match HEAD)"
if [[ "${head_tag}" != "${V4L2LOOPBACK_REF}" ]]; then
  fail "HEAD là ${head_tag}, cần ${V4L2LOOPBACK_REF}"
fi
if ! grep -q 'KERNEL_VERSION(6, 18, 0)' "${V4L2LOOPBACK_DIR}/v4l2loopback.c"; then
  fail "tag ${V4L2LOOPBACK_REF} không có vá kernel >= 6.18 (KERNEL_VERSION(6, 18, 0))"
fi

remove_other_loopback_dkms
if ! dkms status -m v4l2loopback -v "${V4L2LOOPBACK_VERSION}" 2>/dev/null | grep -q .; then
  dkms add "${V4L2LOOPBACK_DIR}"
fi
if dkms status -m v4l2loopback -v "${V4L2LOOPBACK_VERSION}" -k "${krel}" 2>/dev/null | grep -q 'installed'; then
  echo "DKMS v4l2loopback/${V4L2LOOPBACK_VERSION} đã installed cho ${krel}"
else
  dkms install -m v4l2loopback -v "${V4L2LOOPBACK_VERSION}" -k "${krel}"
fi

echo "==> [4/7] Nạp v4l2loopback → /dev/video${THETA_VIDEO_NR}"
install -d /etc/modprobe.d /etc/modules-load.d
cat > /etc/modprobe.d/v4l2loopback-theta.conf <<EOF
# Ricoh Theta X virtual capture node
options v4l2loopback exclusive_caps=1 video_nr=${THETA_VIDEO_NR} card_label=${THETA_CARD_LABEL}
EOF
cat > /etc/modules-load.d/v4l2loopback-theta.conf <<EOF
v4l2loopback
EOF

modprobe -r v4l2loopback 2>/dev/null || true
modprobe v4l2loopback exclusive_caps=1 \
  video_nr="${THETA_VIDEO_NR}" card_label="${THETA_CARD_LABEL}"
if [[ ! -e "/dev/video${THETA_VIDEO_NR}" ]]; then
  fail "/dev/video${THETA_VIDEO_NR} không xuất hiện sau modprobe"
fi
# --list-devices mở /dev/video0 trước. Node đó không mở được thì v4l2-ctl thoát
# cả lệnh, dù loopback nằm ở video1. Hỏi đúng device.
v4l_info="$(v4l2-ctl -d "/dev/video${THETA_VIDEO_NR}" --info 2>&1)" || fail "v4l2-ctl không mở được /dev/video${THETA_VIDEO_NR}: ${v4l_info}"
if ! grep -q "${THETA_CARD_LABEL}" <<<"${v4l_info}"; then
  fail "v4l2-ctl không thấy ${THETA_CARD_LABEL} trên /dev/video${THETA_VIDEO_NR}: ${v4l_info}"
fi

echo "==> [5/7] Clone upstream vào ${THETA_PREFIX}"
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

echo "==> [6/7] Build libuvc-theta, patch sample, build gst_loopback"
cmake -S "${LIBUVC_THETA_DIR}" -B "${LIBUVC_THETA_DIR}/build"
cmake --build "${LIBUVC_THETA_DIR}/build" -j"$(nproc)"
cmake --install "${LIBUVC_THETA_DIR}/build"
ldconfig

bash "${SCRIPT_DIR}/apply-patches.sh"
make -C "${LIBUVC_THETA_SAMPLE_DIR}/gst" clean || true
make -C "${LIBUVC_THETA_SAMPLE_DIR}/gst"
ln -sfn gst_viewer "${LIBUVC_THETA_SAMPLE_DIR}/gst/gst_loopback"
test -x "${GST_LOOPBACK_BIN}"

echo "==> [7/7] Cài udev + systemd"
install -m 0644 "${SCRIPT_DIR}/udev/99-theta-x.rules" /etc/udev/rules.d/99-theta-x.rules
install -m 0644 "${SCRIPT_DIR}/systemd/theta-loopback.service" /etc/systemd/system/theta-loopback.service
install -d /etc/systemd/system/theta-loopback.service.d
install -d "${THETA_PREFIX}/bin"
install -m 0755 "${SCRIPT_DIR}/start-loopback.sh" "${THETA_PREFIX}/bin/start-loopback.sh"
install -m 0755 "${SCRIPT_DIR}/apply-patches.sh" "${THETA_PREFIX}/bin/apply-patches.sh"
install -m 0644 "${SCRIPT_DIR}/theta.conf" "${THETA_PREFIX}/bin/theta.conf"
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
echo "OK. Log: ${LOG}"
echo "  1) Bật LIVE trên Theta X, cắm USB"
echo "  2) lsusb | grep -i ricoh   # kỳ vọng idProduct ${THETA_USB_PID_LIVE}"
echo "  3) v4l2-ctl -d /dev/video${THETA_VIDEO_NR} --info  # kỳ vọng Card type: ${THETA_CARD_LABEL}"
echo "  4) dkms status             # kỳ vọng v4l2loopback/${V4L2LOOPBACK_VERSION} installed cho $(uname -r)"
echo "  5) systemctl status theta-loopback"
echo "  6) Manual: ${THETA_PREFIX}/bin/start-loopback.sh"
echo "  7) Test:   gst-launch-1.0 v4l2src device=/dev/video${THETA_VIDEO_NR} ! videoconvert ! autovideosink sync=false"
