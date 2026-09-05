"""Phase 5/6: risk classification, chunked prediction, polygonization (7/8)."""

from __future__ import annotations

import geopandas as gpd
import numpy as np
import rasterio
from shapely.geometry import box

from prediction.classify_risk import classify, class_name
from prediction.predict_raster import classify_to_raster
from prediction.polygonize import polygonize_high_risk
from region import load_global_config
from tests.conftest import write_tif


def _cfg():
    return load_global_config()


def test_classify_thresholds():
    cfg = _cfg()
    prob = np.array([[0.1, 0.3, 0.5, 0.7, 0.9]], dtype=np.float32)
    cls = classify(prob, cfg["risk_thresholds"])
    assert cls.tolist() == [[1, 2, 3, 4, 5]]


def test_classify_nodata_zero():
    cfg = _cfg()
    prob = np.array([[-9999.0, 0.5]], dtype=np.float32)
    cls = classify(prob, cfg["risk_thresholds"])
    assert cls[0, 0] == 0 and cls[0, 1] == 3


def test_classify_to_raster_alignment(tmp_path, tiny_spec):
    cfg = _cfg()
    prob = np.random.rand(20, 20).astype(np.float32)
    sus = write_tif(tmp_path / "sus.tif", prob, tiny_spec)
    out = tmp_path / "cls.tif"
    classify_to_raster(sus, out, tiny_spec, cfg["risk_thresholds"])
    with rasterio.open(out) as s:
        assert (s.width, s.height) == (20, 20)
        assert str(s.crs) == tiny_spec["crs"]
        cls = s.read(1)
    assert set(np.unique(cls)) <= {1, 2, 3, 4, 5}


def test_polygonize_min_area_filter(tmp_path, tiny_spec, tiny_boundary_gdf):
    cfg = _cfg()
    # one big high-prob blob + one tiny 1-px blob (should be dropped by min_area)
    prob = np.full((20, 20), 0.1, dtype=np.float32)
    prob[2:8, 2:8] = 0.9   # 6x6 px blob
    prob[18, 18] = 0.95    # 1 px blob -> below min_area
    sus = write_tif(tmp_path / "sus.tif", prob, tiny_spec)
    cls_tif = tmp_path / "cls.tif"
    classify_to_raster(sus, cls_tif, tiny_spec, cfg["risk_thresholds"])
    out = tmp_path / "regions.geojson"
    # 1 px = 900 m2 = 0.0009 km2; min_area 0.005 km2 drops the 1-px blob
    gdf = polygonize_high_risk(sus, cls_tif, cfg["polygonize"]["high_risk_classes"],
                               min_area_km2=0.005, risk_thresholds=cfg["risk_thresholds"],
                               out_path=out)
    assert out.exists()
    assert (gdf["area_km2"] >= 0.005).all()
    assert set(gdf["risk_class"]) <= set(cfg["polygonize"]["high_risk_classes"])
    assert str(gdf.crs) in ("EPSG:4326", "urn:ogc:def:crs:OGC::CRS84")
    # attributes present
    for col in ("risk_class", "risk_name", "prob_mean", "prob_max", "area_km2"):
        assert col in gdf.columns
