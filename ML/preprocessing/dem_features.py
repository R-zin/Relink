"""DEM-derived features (plan.md 4.2): elevation, slope, aspect (sin/cos),
curvature. TWI optional/deferred."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import rasterio


def slope_aspect_curvature(dem: np.ndarray, res: float, nodata=-9999.0):
    """Compute slope (deg), aspect (rad), curvature from a DEM on a square grid.

    Uses central-difference gradients (Horn's method simplified). NoData cells
    propagate to outputs.
    """
    dem = dem.astype(np.float64)
    valid = np.isfinite(dem) & (dem != nodata)
    dem_f = np.where(valid, dem, np.nan)

    # fill nan with local mean-ish (simple) to avoid gradient blowup at edges
    dz_dy, dz_dx = np.gradient(dem_f, res)
    dz_dy = np.nan_to_num(dz_dy, nan=0.0)
    dz_dx = np.nan_to_num(dz_dx, nan=0.0)

    slope_rad = np.arctan(np.hypot(dz_dx, dz_dy))
    slope_deg = np.degrees(slope_rad)

    # aspect: direction of downslope, 0=north, clockwise
    aspect_rad = np.arctan2(-dz_dy, -dz_dx)  # mathematical
    aspect = (np.pi / 2 - aspect_rad) % (2 * np.pi)  # convert to compass

    # curvature: second derivatives (profile curvature approximation)
    d2z_dy2 = np.gradient(dz_dy, res, axis=0)
    d2z_dx2 = np.gradient(dz_dx, res, axis=1)
    curvature = -(d2z_dx2 + d2z_dy2)

    for arr in (slope_deg, aspect, curvature):
        arr[~valid] = nodata
    return (
        slope_deg.astype(np.float32),
        aspect.astype(np.float32),
        curvature.astype(np.float32),
    )


def aspect_sin_cos(aspect_rad: np.ndarray, nodata=-9999.0):
    """Circular encoding: 1 deg and 359 deg must not appear far apart."""
    valid = np.isfinite(aspect_rad) & (aspect_rad != nodata)
    a = np.where(valid, aspect_rad, 0.0)
    s = np.sin(a).astype(np.float32)
    c = np.cos(a).astype(np.float32)
    s[~valid] = nodata
    c[~valid] = nodata
    return s, c


def write_feature(path: str | Path, arr: np.ndarray, spec: dict) -> Path:
    from .raster_align import grid_profile

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with rasterio.open(path, "w", **grid_profile(spec)) as ds:
        ds.write(arr.astype(np.float32), 1)
    return path
