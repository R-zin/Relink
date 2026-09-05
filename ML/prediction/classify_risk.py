"""Configurable risk classification (plan.md 7.2)."""

from __future__ import annotations

import numpy as np


def thresholds_to_edges(risk_thresholds: list[dict]) -> tuple[list[float], list[int]]:
    ordered = sorted(risk_thresholds, key=lambda t: t["max"])
    return [t["max"] for t in ordered], [t["class"] for t in ordered]


def classify(prob: np.ndarray, risk_thresholds: list[dict], nodata=-9999.0) -> np.ndarray:
    """Map probabilities to class indices 1..5; NoData -> 0."""
    edges, classes = thresholds_to_edges(risk_thresholds)
    valid = np.isfinite(prob) & (prob != nodata)
    idx = np.digitize(np.clip(prob, 0, 1), edges, right=False)
    out = np.zeros(prob.shape, dtype=np.uint8)
    cls = np.array(classes, dtype=np.uint8)
    out[valid] = cls[np.minimum(idx[valid], len(classes) - 1)]
    return out


def class_name(class_idx: int, risk_thresholds: list[dict]) -> str:
    for t in risk_thresholds:
        if t["class"] == class_idx:
            return t["name"]
    return "NoData"


def class_color(class_idx: int, risk_thresholds: list[dict]) -> str:
    for t in risk_thresholds:
        if t["class"] == class_idx:
            return t["color"]
    return "#000000"


def hex_to_rgb(hx: str) -> tuple[int, int, int]:
    hx = hx.lstrip("#")
    return tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))
