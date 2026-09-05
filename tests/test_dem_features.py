"""Phase 2: DEM-derived features (4.2)."""

from __future__ import annotations

import numpy as np

from preprocessing.dem_features import slope_aspect_curvature, aspect_sin_cos


def test_flat_dem_has_zero_slope():
    dem = np.full((10, 10), 100.0, dtype=np.float32)
    slope, aspect, curvature = slope_aspect_curvature(dem, 30.0)
    assert np.allclose(slope[2:-2, 2:-2], 0.0, atol=1e-4)


def test_linear_ramp_slope_magnitude():
    # dz/dx = 1 m per 30 m pixel -> slope = atan(1/30)
    dem = (np.arange(10)[None, :] * 1.0).repeat(10, axis=0).astype(np.float32)
    slope, _, _ = slope_aspect_curvature(dem, 30.0)
    expected = np.degrees(np.arctan(1.0 / 30.0))
    assert np.allclose(slope[2:-2, 2:-2], expected, atol=0.1)


def test_aspect_circular_encoding_continuity():
    # 1 deg and 359 deg must be close in sin/cos space (not far apart)
    a1 = np.radians(np.array([[1.0]], dtype=np.float32))
    a359 = np.radians(np.array([[359.0]], dtype=np.float32))
    s1, c1 = aspect_sin_cos(a1)
    s359, c359 = aspect_sin_cos(a359)
    dist = np.hypot(s1 - s359, c1 - c359)
    assert dist[0, 0] < 0.1  # nearly identical encodings


def test_nodata_propagates():
    dem = np.full((8, 8), 50.0, dtype=np.float32)
    dem[3, 3] = -9999.0
    slope, aspect, curvature = slope_aspect_curvature(dem, 30.0, nodata=-9999.0)
    assert slope[3, 3] == -9999.0
