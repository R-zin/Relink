"""Region extraction & polygonization (plan.md Phase 6)."""

from __future__ import annotations

from pathlib import Path

import geopandas as gpd
import numpy as np
import rasterio
from rasterio.features import geometry_mask, shapes
from shapely.geometry import shape

from .classify_risk import class_name


def _poly_mask(poly, shape_hw, transform):
    return geometry_mask([poly], out_shape=shape_hw, transform=transform,
                         invert=True, all_touched=True)


def polygonize_high_risk(sus_path: str | Path, class_raster_path: str | Path,
                         high_risk_classes: list[int], min_area_km2: float,
                         risk_thresholds: list[dict], out_path: str | Path,
                         simplify_tolerance_m: float = 0.0) -> gpd.GeoDataFrame:
    """High+Very-High pixels -> polygons (EPSG:4326) with risk class, mean/max
    probability, and area_km2. Components below min_area_km2 are dropped."""
    with rasterio.open(sus_path) as src:
        prob = src.read(1)
        nodata = src.nodata
    with rasterio.open(class_raster_path) as src:
        cls = src.read(1)
        transform = src.transform
        crs = src.crs

    valid = np.isfinite(prob)
    if nodata is not None:
        valid &= prob != nodata

    high_mask = np.isin(cls, high_risk_classes)
    features = []
    for geom, val in shapes(cls.astype(np.uint8), mask=high_mask, transform=transform):
        c = int(val)
        if c not in high_risk_classes:
            continue
        poly = shape(geom)
        area_km2 = poly.area / 1e6
        if area_km2 < min_area_km2:
            continue
        sel = _poly_mask(poly, cls.shape, transform) & (cls == c) & valid
        vals = prob[sel]
        if simplify_tolerance_m > 0:
            poly = poly.simplify(simplify_tolerance_m, preserve_topology=True)
        features.append({
            "geometry": poly,
            "risk_class": c,
            "risk_name": class_name(c, risk_thresholds),
            "prob_mean": float(np.mean(vals)) if vals.size else None,
            "prob_max": float(np.max(vals)) if vals.size else None,
            "area_km2": round(float(area_km2), 4),
        })

    gdf = gpd.GeoDataFrame(features, crs=crs)
    if not gdf.empty:
        gdf = gdf.to_crs("EPSG:4326")
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    gdf.to_file(out_path, driver="GeoJSON")
    return gdf
