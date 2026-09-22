"""Reusable AprilTag pipeline helpers (Phase 1+).

Depends on the official Python wrapper built from ``vendor/apriltag``
(see ``scripts/build-vendor-apriltag.sh``).
"""

from .detector import Detection, TagDetector
from .rectify import DualViewportRectifier, ViewportMaps
from .timing import Stopwatch, ms_since

__all__ = [
    "Detection",
    "TagDetector",
    "DualViewportRectifier",
    "ViewportMaps",
    "Stopwatch",
    "ms_since",
]
