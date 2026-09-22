"""Thin wrapper around vendor/apriltag official Python binding."""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, List, Optional, Sequence, Tuple

import numpy as np

try:
    from apriltag import apriltag as _ApriltagClass
except ImportError as exc:  # pragma: no cover - needs Ubuntu build
    raise ImportError(
        "Không import được module 'apriltag'. "
        "Trên Ubuntu hãy chạy: scripts/build-vendor-apriltag.sh "
        "rồi: source .local/apriltag-env.sh"
    ) from exc


Corner = Tuple[float, float]


@dataclass(frozen=True)
class Detection:
    tag_id: int
    hamming: int
    decision_margin: float
    center: Corner
    corners: Tuple[Corner, Corner, Corner, Corner]  # lb, rb, rt, lt

    @classmethod
    def from_raw(cls, raw: dict) -> "Detection":
        # Official wrap keys: id, hamming, margin, center, lb-rb-rt-lt
        corners_arr = np.asarray(raw["lb-rb-rt-lt"], dtype=np.float64)
        corners = tuple(
            (float(corners_arr[i, 0]), float(corners_arr[i, 1])) for i in range(4)
        )
        center = raw["center"]
        return cls(
            tag_id=int(raw["id"]),
            hamming=int(raw["hamming"]),
            decision_margin=float(raw["margin"]),
            center=(float(center[0]), float(center[1])),
            corners=corners,  # type: ignore[arg-type]
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.tag_id,
            "hamming": self.hamming,
            "decision_margin": self.decision_margin,
            "center": [self.center[0], self.center[1]],
            "corners": [[c[0], c[1]] for c in self.corners],
        }


def _default_nthreads() -> int:
    n = os.cpu_count() or 2
    return max(2, min(4, n))


class TagDetector:
    """Detect ``tagStandard41h12`` (and optionally other families) via vendor lib."""

    def __init__(
        self,
        family: str = "tagStandard41h12",
        *,
        quad_decimate: float = 1.0,
        refine_edges: bool = True,
        nthreads: Optional[int] = None,
        maxhamming: int = 1,
        blur: float = 0.0,
    ) -> None:
        threads = _default_nthreads() if nthreads is None else max(1, int(nthreads))
        self.family = family
        self.quad_decimate = float(quad_decimate)
        self.refine_edges = bool(refine_edges)
        self.nthreads = threads
        self._det = _ApriltagClass(
            family,
            threads=threads,
            maxhamming=maxhamming,
            decimate=float(quad_decimate),
            blur=float(blur),
            refine_edges=bool(refine_edges),
        )

    def detect(self, gray: np.ndarray) -> List[Detection]:
        if gray.ndim != 2:
            raise ValueError("detect() expects a single-channel uint8 image")
        if gray.dtype != np.uint8:
            gray = gray.astype(np.uint8, copy=False)
        raw_list: Sequence[dict] = self._det.detect(gray)
        return [Detection.from_raw(r) for r in raw_list]
