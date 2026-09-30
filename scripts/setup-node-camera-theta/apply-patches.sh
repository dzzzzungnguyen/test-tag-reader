#!/usr/bin/env bash
# apply-patches.sh — vá Theta X (0x2717) + device loopback + chế độ daemon
# Chạy trên Ubuntu, sau khi đã clone libuvc-theta-sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=theta.conf
source "${SCRIPT_DIR}/theta.conf"

SAMPLE_GST="${LIBUVC_THETA_SAMPLE_DIR}/gst"
THETAUVC_C="${SAMPLE_GST}/thetauvc.c"
GST_VIEWER_C="${SAMPLE_GST}/gst_viewer.c"
VIDEO_DEV="/dev/video${THETA_VIDEO_NR}"

if [[ ! -f "${THETAUVC_C}" || ! -f "${GST_VIEWER_C}" ]]; then
  echo "ERROR: chưa clone sample tại ${LIBUVC_THETA_SAMPLE_DIR}" >&2
  exit 1
fi

echo "==> Patch Theta X PID 0x${THETA_USB_PID_LIVE} trong thetauvc.c"
if ! grep -q "USBPID_THETAX_UVC" "${THETAUVC_C}"; then
  if grep -q "USBPID_THETAZ1_UVC" "${THETAUVC_C}"; then
    sed -i "/#define USBPID_THETAZ1_UVC/a #define USBPID_THETAX_UVC 0x${THETA_USB_PID_LIVE}" "${THETAUVC_C}"
  else
    echo "ERROR: không tìm thấy USBPID_THETAZ1_UVC trong ${THETAUVC_C}" >&2
    exit 1
  fi
fi

# Mở rộng mọi chỗ so sánh V||Z1 → thêm || THETAX (idempotent)
python3 - "${THETAUVC_C}" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
if "USBPID_THETAX_UVC" in text and "idProduct == USBPID_THETAX_UVC" in text.replace("desc->", ""):
    # vẫn chạy replace an toàn bên dưới
    pass

if re.search(r"desc->idProduct\s*==\s*USBPID_THETAX_UVC", text):
    print("thetauvc: THETAX idProduct check already present")
else:
    pat = re.compile(
        r"desc->idProduct\s*==\s*USBPID_THETAV_UVC\s*\|\|\s*"
        r"desc->idProduct\s*==\s*USBPID_THETAZ1_UVC"
    )
    new, n = pat.subn(
        lambda m: m.group(0) + " || desc->idProduct == USBPID_THETAX_UVC",
        text,
    )
    if n == 0:
        raise SystemExit("ERROR: không tìm thấy nhánh idProduct V||Z1 để thêm THETAX")
    path.write_text(new)
    print(f"thetauvc: patched {n} idProduct check(s)")
PY

echo "==> Patch gst_viewer.c → ${VIDEO_DEV}, qos=false, THETA_DAEMON"
python3 - "${GST_VIEWER_C}" "${VIDEO_DEV}" <<'PY'
import re, sys
from pathlib import Path

path = Path(sys.argv[1])
video_dev = sys.argv[2]
text = path.read_text()

# 1) pipe_proc gst_loopback
loopback_pipe = (
    'if (strcmp(cmd_name, "gst_loopback") == 0)\n'
    '                pipe_proc = "decodebin ! autovideoconvert ! "\n'
    '                        "video/x-raw,format=I420 ! identity drop-allocation=true !"\n'
    f'                        "v4l2sink device={video_dev} qos=false sync=false";'
)
pat = re.compile(
    r'if\s*\(\s*strcmp\s*\(\s*cmd_name\s*,\s*"gst_loopback"\s*\)\s*==\s*0\s*\)\s*'
    r'pipe_proc\s*=\s*"[^"]*"\s*(?:\n\s*"[^"]*"\s*)*;',
    re.M,
)
text2, n = pat.subn(loopback_pipe, text, count=1)
if n == 0:
    # fallback: thay mọi v4l2sink device=/dev/videoN
    text2, n2 = re.subn(
        r'v4l2sink device=/dev/video\d+(?: qos=false)? sync=false',
        f'v4l2sink device={video_dev} qos=false sync=false',
        text,
    )
    if n2 == 0 and f"v4l2sink device={video_dev}" not in text:
        raise SystemExit("ERROR: không patch được v4l2sink trong gst_viewer.c")
    text = text2
else:
    text = text2

# 2) includes
for inc in ("#include <unistd.h>", "#include <stdlib.h>"):
    if inc not in text:
        text = text.replace("#include <stdio.h>", f"#include <stdio.h>\n{inc}")

# 3) keywait daemon
if "THETA_DAEMON" not in text:
    m = re.search(r"void\s*\*\s*keywait\s*\([^)]*\)\s*\{", text)
    if not m:
        print("WARN: không tìm thấy keywait(); systemd có thể cần StandardInput=socket", file=sys.stderr)
    else:
        insert = (
            m.group(0)
            + "\n"
            + '\tif (getenv("THETA_DAEMON") != NULL) {\n'
            + "\t\tfor (;;) sleep(3600);\n"
            + "\t}\n"
        )
        text = text[: m.start()] + insert + text[m.end() :]

path.write_text(text)
print("gst_viewer.c patched OK")
PY

echo "==> Patches applied"
