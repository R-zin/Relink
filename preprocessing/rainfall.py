"""Rainfall accumulation features (plan.md 4.4): rain_1d, rain_3d, rain_7d
from daily grids."""

from __future__ import annotations

from datetime import date
from pathlib import Path

import numpy as np
import rasterio


def accumulate(daily_arrays: list[np.ndarray], window: int, nodata=-9999.0) -> np.ndarray:
    """Sum the last `window` daily rasters. Any NoData day -> NoData in output."""
    if not daily_arrays:
        raise ValueError("no daily rainfall arrays provided")
    window = min(window, len(daily_arrays))
    # running float32 accumulation to bound memory at region scale (no big stack)
    total = np.zeros_like(daily_arrays[0], dtype=np.float32)
    valid = np.ones(daily_arrays[0].shape, dtype=bool)
    for a in daily_arrays[-window:]:
        a32 = a.astype(np.float32)
        valid &= np.isfinite(a32) & (a32 != nodata)
        total += np.where(np.isfinite(a32) & (a32 != nodata), a32, 0).astype(np.float32)
    total[~valid] = nodata
    return total


def load_daily_series(rain_dir: str | Path):
    """Load sorted daily rainfall rasters -> (dates, arrays, profile)."""
    rain_dir = Path(rain_dir)
    files = sorted(rain_dir.glob("rain_*.tif"))
    if not files:
        raise FileNotFoundError(f"no rainfall grids in {rain_dir}")
    dates, arrays = [], []
    profile = None
    for f in files:
        with rasterio.open(f) as src:
            arrays.append(src.read(1))
            if profile is None:
                profile = dict(transform=src.transform, crs=src.crs, nodata=src.nodata)
        dstr = f.stem.split("_", 1)[1]
        dates.append(date(int(dstr[:4]), int(dstr[4:6]), int(dstr[6:8])))
    return dates, arrays, profile
