"""Equirectangular → dual side viewport (Gnomonic / pinhole) remap maps."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Tuple

import cv2
import numpy as np

Side = Literal["left", "right", "both"]


@dataclass(frozen=True)
class ViewportMaps:
    side: Literal["left", "right"]
    yaw_deg: float
    pitch_deg: float
    fov_deg: float
    out_size: Tuple[int, int]  # (width, height)
    map_x: np.ndarray
    map_y: np.ndarray

    def remap(self, equirect_bgr_or_gray: np.ndarray) -> np.ndarray:
        return cv2.remap(
            equirect_bgr_or_gray,
            self.map_x,
            self.map_y,
            interpolation=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_WRAP,
        )


def _build_gnomonic_maps(
    src_w: int,
    src_h: int,
    out_w: int,
    out_h: int,
    yaw_deg: float,
    pitch_deg: float,
    fov_deg: float,
) -> Tuple[np.ndarray, np.ndarray]:
    """Perspective viewport looking at (yaw, pitch) on an equirect sphere.

    Equirect convention: x → longitude [-pi, pi], y → latitude [pi/2, -pi/2]
    with (0, mid-y) ≈ front. yaw_deg rotates around up-axis (positive = look right).
    """
    yaw = np.deg2rad(yaw_deg)
    pitch = np.deg2rad(pitch_deg)
    fov = np.deg2rad(fov_deg)

    # Horizontal FOV; derive fx,fy assuming square pixels
    f = (out_w / 2.0) / np.tan(fov / 2.0)

    u = np.arange(out_w, dtype=np.float32)
    v = np.arange(out_h, dtype=np.float32)
    uu, vv = np.meshgrid(u, v)

    # Camera rays in viewport frame (x right, y down, z forward)
    x = (uu - (out_w - 1) * 0.5) / f
    y = (vv - (out_h - 1) * 0.5) / f
    z = np.ones_like(x)

    # Normalize
    norm = np.sqrt(x * x + y * y + z * z)
    x, y, z = x / norm, y / norm, z / norm

    # Rotate by pitch (around x) then yaw (around y) — camera look direction
    cp, sp = np.cos(pitch), np.sin(pitch)
    y2 = y * cp - z * sp
    z2 = y * sp + z * cp
    x2 = x

    cy, sy = np.cos(yaw), np.sin(yaw)
    x3 = x2 * cy + z2 * sy
    y3 = y2
    z3 = -x2 * sy + z2 * cy

    lon = np.arctan2(x3, z3)
    lat = np.arcsin(np.clip(y3, -1.0, 1.0))

    map_x = ((lon / (2.0 * np.pi)) + 0.5) * src_w
    map_y = (0.5 - (lat / np.pi)) * src_h

    return map_x.astype(np.float32), map_y.astype(np.float32)


class DualViewportRectifier:
    """Precompute left (yaw=270°) and right (yaw=90°) viewport maps."""

    def __init__(
        self,
        src_size: Tuple[int, int] = (3840, 1920),
        out_size: Tuple[int, int] = (1280, 720),
        fov_deg: float = 70.0,
        yaw_right_deg: float = 90.0,
        yaw_left_deg: float = 270.0,
        pitch_deg: float = 0.0,
    ) -> None:
        src_w, src_h = src_size
        out_w, out_h = out_size
        self.src_size = src_size
        self.out_size = out_size
        self.fov_deg = fov_deg
        self.pitch_deg = pitch_deg

        mx_r, my_r = _build_gnomonic_maps(
            src_w, src_h, out_w, out_h, yaw_right_deg, pitch_deg, fov_deg
        )
        mx_l, my_l = _build_gnomonic_maps(
            src_w, src_h, out_w, out_h, yaw_left_deg, pitch_deg, fov_deg
        )
        self.right = ViewportMaps(
            "right", yaw_right_deg, pitch_deg, fov_deg, out_size, mx_r, my_r
        )
        self.left = ViewportMaps(
            "left", yaw_left_deg, pitch_deg, fov_deg, out_size, mx_l, my_l
        )

    def maps_for(self, side: Side) -> Tuple[ViewportMaps, ...]:
        if side == "left":
            return (self.left,)
        if side == "right":
            return (self.right,)
        return (self.left, self.right)
