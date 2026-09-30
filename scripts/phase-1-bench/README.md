# Phase 1 bench

Grab Theta loopback → dual-viewport remap → AprilTag detect (`vendor/apriltag`) → log timing.

## Prerequisites (Ubuntu)

1. Phase 0 loopback live on `/dev/video1`.
2. Build vendor library once:

```bash
./scripts/build-vendor-apriltag.sh
source .local/apriltag-env.sh
```

3. OpenCV for Python (`python3-opencv` or `pip install -r requirements.txt`).

## Run

```bash
cd /path/to/test-tag-reader
source .local/apriltag-env.sh
export PYTHONPATH="$(pwd)/src:${PYTHONPATH}"
python3 -u scripts/phase-1-bench/run_bench.py --device /dev/video1 --side both
```

Mặc định ghi log kèm timestamp vào `logs/`:

```text
logs/phase1-bench-20260929-155630.log
```

(`--json-log` → `.jsonl`). Không cần `tee /tmp/phase1-bench.log` nữa.

| Flag | Ý nghĩa |
|------|---------|
| `--log-dir DIR` | Thư mục log (default `<repo>/logs`) |
| `--log-file PATH` | Đường dẫn cố định (bỏ qua tên auto) |
| `--no-log-file` | Chỉ console |

See [`docs/phase-1/checklist-bench.md`](../../docs/phase-1/checklist-bench.md).
