"""Simple timing helpers for bench / pipeline logs."""

from __future__ import annotations

import time


def ms_since(t0: float) -> float:
    return (time.perf_counter() - t0) * 1000.0


class Stopwatch:
    """Named split timer: start → lap(name) → ... → total_ms()."""

    def __init__(self) -> None:
        self._t0 = time.perf_counter()
        self._last = self._t0
        self.splits: dict[str, float] = {}

    def lap(self, name: str) -> float:
        now = time.perf_counter()
        ms = (now - self._last) * 1000.0
        self.splits[name] = ms
        self._last = now
        return ms

    def total_ms(self) -> float:
        return (time.perf_counter() - self._t0) * 1000.0
