#!/usr/bin/env python3
"""Phase 1 bench: /dev/videoN → dual remap → vendor apriltag → log ms + debug.

Ubuntu only (needs Phase 0 loopback + built vendor/apriltag Python wrap).

    source .local/apriltag-env.sh
    PYTHONPATH=src:$PYTHONPATH python3 scripts/phase-1-bench/run_bench.py
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np

_REPO_ROOT = Path(__file__).resolve().parents[2]
_SRC = _REPO_ROOT / "src"
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from tag_reader import DualViewportRectifier, Stopwatch, TagDetector  # noqa: E402


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Phase 1 AprilTag bench on Theta loopback")
    p.add_argument("--device", default="/dev/video1", help="V4L2 device path")
    p.add_argument(
        "--side",
        choices=("left", "right", "both"),
        default="both",
        help="Which viewport(s) to remap+detect",
    )
    p.add_argument("--fov", type=float, default=70.0, help="Horizontal FOV degrees")
    p.add_argument("--yaw-right", type=float, default=90.0)
    p.add_argument("--yaw-left", type=float, default=270.0)
    p.add_argument("--out-w", type=int, default=1280)
    p.add_argument("--out-h", type=int, default=720)
    p.add_argument("--decimate", type=float, default=1.0)
    p.add_argument("--threads", type=int, default=None, help="Detector nthreads (default 2..4)")
    p.add_argument("--family", default="tagStandard41h12")
    p.add_argument("--no-preview", action="store_true")
    p.add_argument(
        "--throttle-fps",
        type=float,
        default=12.0,
        help="Max processing rate (0 = every frame)",
    )
    p.add_argument(
        "--json-log",
        action="store_true",
        help="One JSON object per processed frame on stdout",
    )
    p.add_argument("--max-frames", type=int, default=0, help="Stop after N processed (0=forever)")
    return p.parse_args()


def draw_detections(bgr: np.ndarray, detections) -> None:
    for det in detections:
        pts = np.array(det.corners, dtype=np.int32)
        for i in range(4):
            a = (int(pts[i, 0]), int(pts[i, 1]))
            b = (int(pts[(i + 1) % 4, 0]), int(pts[(i + 1) % 4, 1]))
            cv2.line(bgr, a, b, (0, 255, 0), 2)
        c = (int(det.center[0]), int(det.center[1]))
        cv2.putText(
            bgr,
            f"id={det.tag_id} m={det.decision_margin:.1f}",
            (c[0] - 40, c[1] - 10),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (0, 200, 255),
            2,
        )


def main() -> int:
    args = parse_args()

    cap = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
    if not cap.isOpened():
        print(f"ERROR: cannot open {args.device}", file=sys.stderr)
        return 1

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 3840)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1920)
    try:
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    except Exception:
        pass

    ok, frame = cap.read()
    if not ok or frame is None:
        print("ERROR: failed to read first frame", file=sys.stderr)
        return 1

    src_h, src_w = frame.shape[:2]
    print(
        f"stream {args.device} size={src_w}x{src_h} side={args.side} "
        f"fov={args.fov} out={args.out_w}x{args.out_h}",
        file=sys.stderr,
    )

    rectifier = DualViewportRectifier(
        src_size=(src_w, src_h),
        out_size=(args.out_w, args.out_h),
        fov_deg=args.fov,
        yaw_right_deg=args.yaw_right,
        yaw_left_deg=args.yaw_left,
    )
    detector = TagDetector(
        family=args.family,
        quad_decimate=args.decimate,
        refine_edges=True,
        nthreads=args.threads,
    )
    print(
        f"detector family={detector.family} decimate={detector.quad_decimate} "
        f"nthreads={detector.nthreads}",
        file=sys.stderr,
    )

    viewports = rectifier.maps_for(args.side)
    min_interval = (1.0 / args.throttle_fps) if args.throttle_fps > 0 else 0.0
    next_t = time.perf_counter()
    processed = 0
    hit_frames = 0

    while True:
        now = time.perf_counter()
        if min_interval > 0 and now < next_t:
            cap.grab()
            time.sleep(min(0.005, next_t - now))
            continue
        next_t = now + min_interval

        sw = Stopwatch()
        ok, frame = cap.read()
        if not ok or frame is None:
            print("WARN: read failed", file=sys.stderr)
            continue
        t_grab = sw.lap("grab")

        remapped = [(vp, vp.remap(frame)) for vp in viewports]
        t_remap = sw.lap("remap")

        all_dets = []
        view_images = []
        for vp, view in remapped:
            gray = cv2.cvtColor(view, cv2.COLOR_BGR2GRAY) if view.ndim == 3 else view
            dets = detector.detect(gray)
            for d in dets:
                all_dets.append({"side": vp.side, "yaw_deg": vp.yaw_deg, **d.to_dict()})
            view_images.append((vp.side, view, dets))
        t_detect = sw.lap("detect")
        t_total = sw.total_ms()

        processed += 1
        if all_dets:
            hit_frames += 1

        fps = 1000.0 / t_total if t_total > 0 else 0.0
        record = {
            "frame": processed,
            "t_grab_ms": round(t_grab, 2),
            "t_remap_ms": round(t_remap, 2),
            "t_detect_ms": round(t_detect, 2),
            "t_total_ms": round(t_total, 2),
            "fps": round(fps, 2),
            "hit_rate": round(hit_frames / processed, 3),
            "detections": all_dets,
        }

        if args.json_log:
            print(json.dumps(record, ensure_ascii=False))
        else:
            ids = [d["id"] for d in all_dets]
            print(
                f"#{processed} grab={record['t_grab_ms']:.1f} "
                f"remap={record['t_remap_ms']:.1f} detect={record['t_detect_ms']:.1f} "
                f"total={record['t_total_ms']:.1f} ms fps~{record['fps']:.1f} "
                f"ids={ids} hit_rate={record['hit_rate']:.2f}"
            )

        if not args.no_preview:
            panels = [cv2.resize(frame, (640, 360))]
            for side, view, dets in view_images:
                vis = view.copy()
                draw_detections(vis, dets)
                cv2.putText(
                    vis,
                    side,
                    (12, 28),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.9,
                    (255, 255, 255),
                    2,
                )
                panels.append(cv2.resize(vis, (640, 360)))
            row = cv2.hconcat(panels[:3])
            cv2.imshow("phase-1-bench", row)
            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q")):
                break

        if args.max_frames and processed >= args.max_frames:
            break

    cap.release()
    if not args.no_preview:
        cv2.destroyAllWindows()
    print(
        f"done processed={processed} hit_frames={hit_frames} "
        f"hit_rate={hit_frames / max(processed, 1):.3f}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
