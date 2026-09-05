"""Phase 0: region/AOI framework, config-driven, grid derivation (1A / 2.1)."""

from __future__ import annotations

from region import Region, load_global_config


def test_load_kerala_region():
    r = Region.from_config("kerala")
    assert r.name == "Kerala"
    assert r.crs == "EPSG:32643"
    assert r.target_resolution_m == 30
    assert "Kerala" in str(r.outputs_dir)


def test_region_switch_is_config_only():
    """Two regions load from configs with no code changes (DoD 7)."""
    k = Region.from_config("kerala")
    i = Region.from_config("idukki")
    assert k.name != i.name
    assert k.outputs_dir != i.outputs_dir
    # same framework API works for both
    for r in (k, i):
        spec = r.grid_spec()
        assert spec["width"] > 0 and spec["height"] > 0
        assert spec["resolution"] == r.target_resolution_m


def test_grid_contains_boundary_with_buffer():
    r = Region.from_config("kerala")
    spec = r.grid_spec()
    b = r.boundary()
    minx, miny, maxx, maxy = b.total_bounds
    gx0, gy0, gx1, gy1 = spec["bounds"]
    # grid extent contains boundary plus the configured buffer
    assert gx0 < minx and gy0 < miny and gx1 > maxx and gy1 > maxy


def test_grid_pixels_are_whole_multiples():
    r = Region.from_config("kerala")
    spec = r.grid_spec()
    res = spec["resolution"]
    width = round((spec["bounds"][2] - spec["bounds"][0]) / res)
    height = round((spec["bounds"][3] - spec["bounds"][1]) / res)
    assert width == spec["width"] and height == spec["height"]


def test_global_config_loads():
    cfg = load_global_config()
    assert "risk_thresholds" in cfg and len(cfg["risk_thresholds"]) == 5
    assert "features" in cfg and "random_seed" in cfg
