"""DoD 7: a second region runs the same pipeline with only config + boundary
changes -- no code edits. Uses cached Idukki outputs (fast)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
import rasterio

from region import Region


REQUIRED = ["susceptibility.tif", "risk_classes.tif", "risk_regions.geojson",
            "model_metrics.json", "source_metadata.json", "best_model.joblib"]


@pytest.mark.slow
def test_idukki_outputs_complete():
    r = Region.from_config("idukki")
    for name in REQUIRED:
        assert (r.outputs_dir / name).exists(), f"missing {name}"


@pytest.mark.slow
def test_idukki_rasters_aligned_to_grid():
    r = Region.from_config("idukki")
    spec = r.grid_spec()
    for name in ("susceptibility.tif", "risk_classes.tif"):
        with rasterio.open(r.outputs_dir / name) as src:
            assert src.width == spec["width"] and src.height == spec["height"]
            assert str(src.crs) == spec["crs"]
            assert tuple(src.transform) == tuple(spec["transform"])


@pytest.mark.slow
def test_metrics_json_structure():
    r = Region.from_config("idukki")
    m = json.loads((r.outputs_dir / "model_metrics.json").read_text())
    assert set(m["models"]) == {"logistic_regression", "random_forest", "xgboost"}
    assert m["best_model"] in m["models"]
    for name, entry in m["models"].items():
        assert "val" in entry and "pr_auc" in entry["val"]


@pytest.mark.slow
def test_source_metadata_records_native_resolutions():
    r = Region.from_config("idukki")
    meta = json.loads((r.outputs_dir / "source_metadata.json").read_text())
    assert meta["region"] == "Idukki"
    # rainfall native-resolution caveat recorded (resolution honesty)
    assert "25 km" in json.dumps(meta) or "0.25" in json.dumps(meta)
