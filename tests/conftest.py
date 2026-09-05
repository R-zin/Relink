"""Shared fixtures: a tiny in-memory region for fast unit tests."""

from __future__ import annotations

import json
from pathlib import Path

import geopandas as gpd
import numpy as np
import pytest
import rasterio
from affine import Affine
from shapely.geometry import box, mapping


@pytest.fixture()
def tiny_boundary(tmp_path) -> Path:
    """A small square boundary in EPSG:4326 (~0.1 deg)."""
    poly = box(76.0, 9.0, 76.1, 9.1)
    gj = {
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "properties": {"name": "Tiny"},
            "geometry": mapping(poly),
        }],
    }
    p = tmp_path / "boundary.geojson"
    p.write_text(json.dumps(gj))
    return p


@pytest.fixture()
def tiny_spec():
    """A small grid spec: 20x20 px at 30 m, EPSG:32643."""
    res = 30.0
    w = h = 20
    minx, maxy = 400000.0, 1000000.0
    return {
        "crs": "EPSG:32643",
        "transform": Affine(res, 0.0, minx, 0.0, -res, maxy),
        "width": w,
        "height": h,
        "resolution": res,
        "bounds": (minx, maxy - h * res, minx + w * res, maxy),
    }


@pytest.fixture()
def tiny_boundary_gdf(tiny_spec):
    poly = box(tiny_spec["bounds"][0], tiny_spec["bounds"][1],
               tiny_spec["bounds"][2], tiny_spec["bounds"][3])
    return gpd.GeoDataFrame(geometry=[poly], crs=tiny_spec["crs"])


def write_tif(path: Path, arr: np.ndarray, spec: dict, dtype="float32", nodata=-9999.0):
    path.parent.mkdir(parents=True, exist_ok=True)
    with rasterio.open(
        path, "w", driver="GTiff", dtype=dtype, width=arr.shape[1], height=arr.shape[0],
        count=1, crs=spec["crs"], transform=spec["transform"], nodata=nodata,
    ) as dst:
        dst.write(arr.astype(dtype), 1)
    return path
