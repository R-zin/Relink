"""Chunked pixel-wise prediction (plan.md 7.1).

Kerala at 30 m is ~43M pixels, so prediction is row-windowed to bound memory.
Output is float32 probability 0-1, on the common grid, masked to the boundary.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import rasterio
import rasterio.windows

from .classify_risk import classify, hex_to_rgb
from preprocessing.raster_align import grid_profile


def predict_susceptibility(model, feature_names: list[str], stack_dir: str | Path,
                           spec: dict, valid_mask: np.ndarray, out_path: str | Path,
                           block_rows: int = 256, categorical: list[str] | None = None,
                           nodata=-9999.0) -> Path:
    stack_dir = Path(stack_dir)
    h, w = spec["height"], spec["width"]
    categorical = categorical or []

    srcs = {n: rasterio.open(stack_dir / f"{n}.tif") for n in feature_names}
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    profile = grid_profile(spec, dtype="float32", nodata=nodata)

    try:
        with rasterio.open(out_path, "w", **profile) as dst:
            for r0 in range(0, h, block_rows):
                r1 = min(h, r0 + block_rows)
                window = rasterio.windows.Window(0, r0, w, r1 - r0)
                block = np.full((r1 - r0, w), nodata, dtype=np.float32)
                vmask = valid_mask[r0:r1, :]
                if vmask.any():
                    cols = {}
                    for n, src in srcs.items():
                        cols[n] = src.read(1, window=window)[vmask].astype(np.float32)
                    X = pd.DataFrame(cols)
                    for c in categorical:
                        if c in X.columns:
                            X[c] = X[c].astype("category")
                    block[vmask] = model.predict_proba(X)[:, 1].astype(np.float32)
                dst.write(block, 1, window=window)
    finally:
        for src in srcs.values():
            src.close()
    return out_path


def classify_to_raster(sus_path: str | Path, out_path: str | Path, spec: dict,
                       risk_thresholds: list[dict]) -> Path:
    with rasterio.open(sus_path) as src:
        prob = src.read(1)
        nodata = src.nodata
    cls = classify(prob, risk_thresholds, nodata=nodata if nodata is not None else -9999.0)
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    profile = grid_profile(spec, dtype="uint8", nodata=0)
    colormap = {t["class"]: (*hex_to_rgb(t["color"]), 255) for t in risk_thresholds}
    with rasterio.open(out_path, "w", **profile) as dst:
        dst.write(cls, 1)
        dst.write_colormap(1, colormap)
    return out_path
