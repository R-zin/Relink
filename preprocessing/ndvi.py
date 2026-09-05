"""NDVI from Sentinel-2 B4/B8 (plan.md 4.3). NDVI = (B8 - B4) / (B8 + B4)."""

from __future__ import annotations

import numpy as np


def compute_ndvi(red: np.ndarray, nir: np.ndarray, nodata=-9999.0) -> np.ndarray:
    red = red.astype(np.float64)
    nir = nir.astype(np.float64)
    valid = (
        np.isfinite(red) & np.isfinite(nir)
        & (red != nodata) & (nir != nodata)
        & ((nir + red) != 0)
    )
    ndvi = np.full(red.shape, nodata, dtype=np.float32)
    ndvi_val = (nir - red) / (nir + red)
    ndvi[valid] = np.clip(ndvi_val[valid], -1.0, 1.0)
    return ndvi
