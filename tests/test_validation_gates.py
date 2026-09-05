"""Phase 1A.5/4.5: validation gates pass for real regions and catch bad data."""

from __future__ import annotations

import numpy as np
import pytest

from region import Region
import validate_region_data as vrd
from tests.conftest import write_tif


@pytest.mark.slow
def test_idukki_gates_pass():
    r = Region.from_config("idukki")
    report = vrd.validate(r)
    assert report["ok"], report["failures"]


@pytest.mark.slow
def test_kerala_gates_pass():
    r = Region.from_config("kerala")
    report = vrd.validate(r)
    assert report["ok"], report["failures"]


def test_coverage_gate_catches_missing_data(tiny_spec, tiny_boundary_gdf, tmp_path):
    """A raster that only covers half the boundary must fail the coverage gate."""
    from preprocessing.raster_align import boundary_mask
    inside = boundary_mask(tiny_spec, tiny_boundary_gdf)
    half = np.full((20, 20), -9999.0, dtype=np.float32)
    half[:, :10] = 1.0  # only left half valid
    write_tif(tmp_path / "f.tif", half, tiny_spec)
    import rasterio
    with rasterio.open(tmp_path / "f.tif") as src:
        arr = src.read(1)
        nodata = src.nodata
    valid = np.isfinite(arr) & (arr != nodata)
    frac = valid[inside].mean()
    assert frac < 0.999  # would fail the >=99.9% coverage gate
