"""Phase 2/1A.5: raster alignment resampling rules + shared validity mask (4.1/4.5)."""

from __future__ import annotations

import numpy as np
from rasterio.warp import Resampling

from preprocessing.raster_align import (
    resampling_for, boundary_mask, shared_validity_mask, grid_profile,
)
from tests.conftest import write_tif


def test_resampling_rules():
    # continuous -> bilinear, categorical -> nearest (plan.md 4.1)
    assert resampling_for("elev") == Resampling.bilinear
    assert resampling_for("ndvi") == Resampling.bilinear
    assert resampling_for("rain_1d") == Resampling.bilinear
    assert resampling_for("lulc") == Resampling.nearest
    assert resampling_for("geology") == Resampling.nearest


def test_boundary_mask(tiny_spec, tiny_boundary_gdf):
    m = boundary_mask(tiny_spec, tiny_boundary_gdf)
    assert m.shape == (tiny_spec["height"], tiny_spec["width"])
    assert m.all()  # boundary == grid extent here


def test_shared_validity_mask_requires_all_layers(tmp_path, tiny_spec, tiny_boundary_gdf):
    good = np.ones((20, 20), dtype=np.float32)
    bad = np.ones((20, 20), dtype=np.float32)
    bad[5, 5] = -9999.0  # one invalid pixel in layer b
    write_tif(tmp_path / "a.tif", good, tiny_spec)
    write_tif(tmp_path / "b.tif", bad, tiny_spec)
    valid = shared_validity_mask(tmp_path, ["a", "b"], tiny_spec, tiny_boundary_gdf)
    assert valid.sum() == 20 * 20 - 1
    assert not valid[5, 5]


def test_shared_validity_mask_respects_boundary(tmp_path, tiny_spec):
    # boundary only covers half the grid -> mask excludes the rest
    import geopandas as gpd
    from shapely.geometry import box
    gx0, gy0, gx1, gy1 = tiny_spec["bounds"]
    half = box(gx0, gy0, (gx0 + gx1) / 2, gy1)
    b = gpd.GeoDataFrame(geometry=[half], crs=tiny_spec["crs"])
    write_tif(tmp_path / "a.tif", np.ones((20, 20), dtype=np.float32), tiny_spec)
    valid = shared_validity_mask(tmp_path, ["a"], tiny_spec, b)
    assert valid.sum() < 20 * 20
