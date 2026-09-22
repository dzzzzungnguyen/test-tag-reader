#!/usr/bin/env bash
# build-vendor-apriltag.sh — build AprilTag 3 (+ Python wrap) từ vendor/apriltag
# CHẠY TRÊN UBUNTU. Không dùng để build trên Windows.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${REPO_ROOT}/vendor/apriltag"
BUILD="${SRC}/build"
PREFIX="${REPO_ROOT}/.local/apriltag"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: script này chỉ dành cho Ubuntu/Linux." >&2
  exit 1
fi

if [[ ! -f "${SRC}/CMakeLists.txt" ]]; then
  echo "ERROR: không thấy ${SRC}/CMakeLists.txt" >&2
  exit 1
fi

echo "==> Deps gợi ý (nếu chưa có):"
echo "    sudo apt-get install -y build-essential cmake ninja-build \\"
echo "      python3-dev python3-numpy python3-opencv libopencv-dev"

mkdir -p "${PREFIX}"

echo "==> Configure ${SRC} → ${BUILD} (prefix=${PREFIX})"
cmake -S "${SRC}" -B "${BUILD}" -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_PYTHON_WRAPPER=ON

echo "==> Build & install"
cmake --build "${BUILD}" --target install -j"$(nproc)"

PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
SITE="${PREFIX}/lib/python${PY_VER}/site-packages"
LIBDIR="${PREFIX}/lib"

# Một số distro đặt lib vào lib/x86_64-linux-gnu
if [[ ! -d "${LIBDIR}" ]] && [[ -d "${PREFIX}/lib64" ]]; then
  LIBDIR="${PREFIX}/lib64"
fi

ENV_FILE="${REPO_ROOT}/.local/apriltag-env.sh"
cat > "${ENV_FILE}" <<EOF
# Source trước khi chạy bench Phase 1:
#   source ${ENV_FILE}
export PYTHONPATH="${SITE}\${PYTHONPATH:+:\$PYTHONPATH}"
export LD_LIBRARY_PATH="${LIBDIR}\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
# Thêm path multiarch nếu có
if [ -d "${PREFIX}/lib/$(uname -m)-linux-gnu" ]; then
  export LD_LIBRARY_PATH="${PREFIX}/lib/$(uname -m)-linux-gnu:\$LD_LIBRARY_PATH"
fi
EOF

echo
echo "OK. Kiểm tra:"
echo "  source ${ENV_FILE}"
echo "  python3 -c \"from apriltag import apriltag; print('apriltag OK', apriltag)\""
echo
echo "Rồi chạy bench:"
echo "  cd ${REPO_ROOT}"
echo "  source ${ENV_FILE}"
echo "  PYTHONPATH=${REPO_ROOT}/src:\$PYTHONPATH python3 scripts/phase-1-bench/run_bench.py"
