#!/usr/bin/env bash
# install-units.sh — cập nhật script + systemd (không rebuild libuvc/DKMS).
# Dùng khi chỉ cần vá watchdog / healthcheck trên máy đã install.sh trước đó.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=theta.conf
source "${SCRIPT_DIR}/theta.conf"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: chỉ chạy trên Ubuntu/Linux." >&2
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Chạy với sudo: sudo $0" >&2
  exit 1
fi

install -d "${THETA_PREFIX}/bin"
install -d /etc/systemd/system/theta-loopback.service.d

install -m 0755 "${SCRIPT_DIR}/start-loopback.sh" "${THETA_PREFIX}/bin/start-loopback.sh"
install -m 0755 "${SCRIPT_DIR}/check-stream.sh" "${THETA_PREFIX}/bin/check-stream.sh"
install -m 0755 "${SCRIPT_DIR}/wait-stream-ready.sh" "${THETA_PREFIX}/bin/wait-stream-ready.sh"
install -m 0755 "${SCRIPT_DIR}/watchdog-loopback.sh" "${THETA_PREFIX}/bin/watchdog-loopback.sh"
install -m 0755 "${SCRIPT_DIR}/apply-patches.sh" "${THETA_PREFIX}/bin/apply-patches.sh"
install -m 0755 "${SCRIPT_DIR}/status.sh" "${THETA_PREFIX}/bin/status.sh"
install -m 0644 "${SCRIPT_DIR}/theta.conf" "${THETA_PREFIX}/bin/theta.conf"

install -m 0644 "${SCRIPT_DIR}/udev/99-theta-x.rules" /etc/udev/rules.d/99-theta-x.rules
install -m 0644 "${SCRIPT_DIR}/systemd/theta-loopback.service" /etc/systemd/system/theta-loopback.service
install -m 0644 "${SCRIPT_DIR}/systemd/theta-loopback-watchdog.service" \
  /etc/systemd/system/theta-loopback-watchdog.service
install -m 0644 "${SCRIPT_DIR}/systemd/theta-loopback-watchdog.timer" \
  /etc/systemd/system/theta-loopback-watchdog.timer

cat > /etc/systemd/system/theta-loopback.service.d/override.conf <<EOF
[Service]
Environment=THETA_DAEMON=1
Environment=LD_LIBRARY_PATH=/usr/local/lib
EnvironmentFile=-${THETA_PREFIX}/bin/theta.conf
ExecStart=
ExecStart=${THETA_PREFIX}/bin/start-loopback.sh
ExecStartPost=
ExecStartPost=${THETA_PREFIX}/bin/wait-stream-ready.sh
EOF

udevadm control --reload-rules
systemctl daemon-reload
systemctl enable theta-loopback.service
systemctl enable --now theta-loopback-watchdog.timer

echo "OK. Units installed under ${THETA_PREFIX}/bin + systemd."
echo "  systemctl status theta-loopback-watchdog.timer"
echo "  ${THETA_PREFIX}/bin/check-stream.sh"
echo "  ${THETA_PREFIX}/bin/status.sh"
