"""Phase 2: NDVI (4.3) and rainfall accumulations (4.4)."""

from __future__ import annotations

import numpy as np

from preprocessing.ndvi import compute_ndvi
from preprocessing.rainfall import accumulate


def test_ndvi_basic():
    red = np.array([[0.1]], dtype=np.float32)
    nir = np.array([[0.5]], dtype=np.float32)
    ndvi = compute_ndvi(red, nir)
    assert np.isclose(ndvi[0, 0], (0.5 - 0.1) / (0.5 + 0.1))


def test_ndvi_nodata_and_zero_denominator():
    red = np.array([[0.0, -9999.0]], dtype=np.float32)
    nir = np.array([[0.0, 0.5]], dtype=np.float32)
    ndvi = compute_ndvi(red, nir)
    assert ndvi[0, 0] == -9999.0   # zero denominator
    assert ndvi[0, 1] == -9999.0   # nodata input


def test_rainfall_windows():
    days = [np.full((2, 2), float(i), dtype=np.float32) for i in range(1, 8)]
    assert np.allclose(accumulate(days, 1), 7.0)
    assert np.allclose(accumulate(days, 3), 5 + 6 + 7)
    assert np.allclose(accumulate(days, 7), sum(range(1, 8)))


def test_rainfall_nodata_day_invalidates():
    days = [np.ones((2, 2), dtype=np.float32) for _ in range(3)]
    days[1][0, 0] = -9999.0
    acc = accumulate(days, 3)
    assert acc[0, 0] == -9999.0
    assert acc[1, 1] == 3.0
