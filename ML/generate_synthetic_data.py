"""Synthetic data generator (Phase 1 stand-in for real acquisition).

Real acquisition downloads SRTM / Sentinel-2 / ESA WorldCover / IMD / GSI and
clips each to the region AOI (plan.md Phase 1). That requires network access
and source accounts. This generator creates *plausible synthetic* raw rasters
at each source's native resolution/CRS so the ENTIRE pipeline (reproject ->
clip -> align -> dataset -> train -> predict -> polygonize -> API) can be
developed and tested offline. Swap in real downloads later; only the raw
inputs change, never the downstream code.

Synthetic truth: a hidden susceptibility field driven by slope, NDVI and
rainfall generates landslide points, so models have a learnable signal.
"""

from __future__ import annotations

import argparse
import json
from datetime import date, timedelta
from pathlib import Path

import geopandas as gpd
import numpy as np
import rasterio
from affine import Affine
from pyproj import CRS
from rasterio.crs import CRS as RioCRS
from rasterio.transform import from_bounds
from shapely.geometry import Point

from region import Region, load_global_config

NATIVE = {
    "dem": {"res": 90.0, "crs": "EPSG:4326"},        # SRTM ~3 arcsec (~90 m)
    "ndvi_red": {"res": 60.0, "crs": "EPSG:32643"},  # Sentinel-2 B4 ~10-60 m
    "ndvi_nir": {"res": 60.0, "crs": "EPSG:32643"},  # Sentinel-2 B8
    "landcover": {"res": 100.0, "crs": "EPSG:4326"},  # ESA WorldCover 10 m (coarsened)
    "rainfall": {"res": 0.25, "crs": "EPSG:4326"},   # IMD 0.25 deg
}


def _grid_for(region: Region, native_res: float, native_crs: str, buffer_frac: float = 0.10):
    """Grid covering the boundary extent (+buffer) in the native CRS/resolution."""
    b = region.boundary(native_crs)
    minx, miny, maxx, maxy = b.total_bounds
    dx, dy = (maxx - minx) * buffer_frac, (maxy - miny) * buffer_frac
    minx, maxx, miny, maxy = minx - dx, maxx + dx, miny - dy, maxy + dy
    width = max(4, int(np.ceil((maxx - minx) / native_res)))
    height = max(4, int(np.ceil((maxy - miny) / native_res)))
    transform = from_bounds(minx, miny, maxx, maxy, width, height)
    return transform, width, height, RioCRS.from_user_input(native_crs)


def _write_tif(path: Path, arr: np.ndarray, transform: Affine, crs, dtype: str,
               nodata) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    profile = {
        "driver": "GTiff",
        "dtype": dtype,
        "width": arr.shape[1],
        "height": arr.shape[0],
        "count": 1,
        "crs": crs,
        "transform": transform,
        "nodata": nodata,
        "compress": "deflate",
    }
    with rasterio.open(path, "w", **profile) as dst:
        dst.write(arr.astype(dtype), 1)


def _smooth_noise(rng: np.random.Generator, shape, scale: float) -> np.ndarray:
    """Low-frequency random field via upsampled coarse noise."""
    from scipy.ndimage import zoom

    coarse = rng.standard_normal((max(2, shape[0] // 12), max(2, shape[1] // 12)))
    zy, zx = shape[0] / coarse.shape[0], shape[1] / coarse.shape[1]
    return zoom(coarse, (zy, zx), order=3)[: shape[0], : shape[1]] * scale


def generate(region: Region, global_cfg: dict, seed: int = 7) -> dict:
    rng = np.random.default_rng(seed)
    raw = region.raw_dir
    summary = {}

    # ---- DEM (native ~90 m EPSG:4326): a Western-Ghats-like elevation field
    tr, w, h, crs = _grid_for(region, NATIVE["dem"]["res"], NATIVE["dem"]["crs"])
    yy, xx = np.mgrid[0:h, 0:w]
    # elevation rises toward the east (Ghats), plus smooth relief + noise
    base = 1800 * (xx / w) ** 1.5
    relief = 250 * np.sin(yy / h * 9.0) * np.cos(xx / w * 7.0)
    dem = base + relief + _smooth_noise(rng, (h, w), 120.0) + rng.normal(0, 8, (h, w))
    dem = np.clip(dem, 0, 2600).astype(np.float32)
    _write_tif(raw / "dem" / "dem_raw.tif", dem, tr, crs, "float32", -9999.0)
    summary["dem"] = {"path": str(raw / "dem" / "dem_raw.tif"), "native_res": "90 m",
                      "native_crs": "EPSG:4326", "source": "SYNTHETIC (stand-in for NASA SRTM)"}

    # ---- Sentinel-2 B4/B8 (native 60 m EPSG:32643) -> NDVI signal later
    tr, w, h, crs = _grid_for(region, NATIVE["ndvi_red"]["res"], NATIVE["ndvi_red"]["crs"])
    yy, xx = np.mgrid[0:h, 0:w]
    # healthy vegetation on western lowlands, sparse/bare on steep eastern Ghats
    veg = 0.65 - 0.35 * (xx / w) + _smooth_noise(rng, (h, w), 0.15)
    veg = np.clip(veg, 0.02, 0.9)
    red = (0.10 - 0.5 * veg).clip(0.02, 0.3).astype(np.float32)
    nir = (0.15 + 0.55 * veg).clip(0.05, 0.9).astype(np.float32)
    _write_tif(raw / "sentinel" / "b04_red.tif", red, tr, crs, "float32", -9999.0)
    _write_tif(raw / "sentinel" / "b08_nir.tif", nir, tr, crs, "float32", -9999.0)
    summary["ndvi"] = {"red": str(raw / "sentinel" / "b04_red.tif"),
                       "nir": str(raw / "sentinel" / "b08_nir.tif"),
                       "native_res": "60 m", "native_crs": "EPSG:32643",
                       "source": "SYNTHETIC (stand-in for Sentinel-2 B4/B8 median composite)"}

    # ---- Land cover (native 100 m EPSG:4326): categorical
    tr, w, h, crs = _grid_for(region, NATIVE["landcover"]["res"], NATIVE["landcover"]["crs"])
    yy, xx = np.mgrid[0:h, 0:w]
    lulc = np.full((h, w), 10, dtype=np.uint8)          # 10 = tree cover
    lulc[xx / w > 0.75] = 30                             # 30 = grassland/bare east
    lulc[(xx / w < 0.12)] = 50                           # 50 = built-up coastal strip
    lulc[(yy / h > 0.8) & (xx / w < 0.3)] = 40           # 40 = cropland south-west
    noise_mask = rng.random((h, w)) < 0.03
    lulc[noise_mask] = rng.choice([10, 20, 30, 40, 50], noise_mask.sum())
    _write_tif(raw / "landcover" / "landcover_raw.tif", lulc, tr, crs, "uint8", 255)
    summary["landcover"] = {"path": str(raw / "landcover" / "landcover_raw.tif"),
                            "native_res": "100 m", "native_crs": "EPSG:4326",
                            "source": "SYNTHETIC (stand-in for ESA WorldCover)"}

    # ---- Rainfall (native 0.25 deg EPSG:4326): 14 daily grids
    tr, w, h, crs = _grid_for(region, NATIVE["rainfall"]["res"], NATIVE["rainfall"]["crs"])
    rain_dir = raw / "rainfall"
    rain_dir.mkdir(parents=True, exist_ok=True)
    start = date(2018, 8, 1)  # around the 2018 Kerala floods window
    for i in range(14):
        d = start + timedelta(days=i)
        # a heavy-rain spell mid-window, spatially structured
        intensity = 5 + 60 * np.exp(-((i - 8) ** 2) / 6.0)
        yy, xx = np.mgrid[0:h, 0:w]
        field = intensity * (0.6 + 0.4 * np.sin(xx / w * 3.0) * np.cos(yy / h * 2.0))
        field += rng.gamma(2.0, 3.0, (h, w))
        field = np.clip(field, 0, 300).astype(np.float32)
        _write_tif(rain_dir / f"rain_{d:%Y%m%d}.tif", field, tr, crs, "float32", -9999.0)
    summary["rainfall"] = {
        "dir": str(rain_dir), "days": 14, "native_res": "0.25 deg (~25 km)",
        "native_crs": "EPSG:4326",
        "source": "SYNTHETIC (stand-in for IMD 0.25 deg daily gridded rainfall)",
        "note": "native ~25 km; resampling to 30 m grid interpolates, does NOT create 30 m accuracy",
    }

    # ---- Hidden true susceptibility -> landslide inventory points
    # higher on steep east (high dem), moderate veg loss, and heavy-rain core
    spec = region.grid_spec()
    gw, gh = spec["width"], spec["height"]
    trg = spec["transform"]
    yy, xx = np.mgrid[0:gh, 0:gw]
    dem_g = zoom_to(dem, (gh, gw))
    slope_proxy = np.gradient(dem_g)[0] ** 2 + np.gradient(dem_g)[1] ** 2
    veg_g = zoom_to(veg, (gh, gw))
    logit = (
        -6.0
        + 3.2 * (slope_proxy / (slope_proxy.max() + 1e-6))
        + 1.4 * (dem_g / (dem_g.max() + 1e-6))
        - 1.8 * veg_g
        + rng.normal(0, 0.4, (gh, gw))
    )
    p = 1 / (1 + np.exp(-logit))
    # sample landslide points weighted by p, inside boundary
    boundary = region.boundary(str(spec["crs"]))
    union = boundary.union_all()
    flat = p.ravel()
    idx = rng.choice(flat.size, size=min(600, flat.size), replace=False,
                     p=flat / flat.sum())
    pts = []
    for i in idx:
        r, c = divmod(int(i), gw)
        x, y = trg * (c + 0.5, r + 0.5)
        pt = Point(float(x), float(y))
        if union.contains(pt):
            pts.append(pt)
        if len(pts) >= 250:
            break
    inv = gpd.GeoDataFrame(
        {"date": [str(start + timedelta(days=8))] * len(pts),
         "source": ["SYNTHETIC (stand-in for GSI inventory)"] * len(pts)},
        geometry=pts,
        crs=spec["crs"],
    ).to_crs("EPSG:4326")
    inv_path = raw / "landslides" / "inventory.geojson"
    inv_path.parent.mkdir(parents=True, exist_ok=True)
    inv.to_file(inv_path, driver="GeoJSON")
    summary["landslides"] = {"path": str(inv_path), "count_positive": len(inv),
                             "source": "SYNTHETIC (stand-in for GSI landslide inventory)"}

    out = raw / "synthetic_summary.json"
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)
    return summary


def zoom_to(arr: np.ndarray, shape) -> np.ndarray:
    from scipy.ndimage import zoom

    zy, zx = shape[0] / arr.shape[0], shape[1] / arr.shape[1]
    return zoom(arr, (zy, zx), order=1)[: shape[0], : shape[1]]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", default="kerala")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    region = Region.from_config(args.region)
    cfg = load_global_config()
    summary = generate(region, cfg, seed=args.seed)
    print(json.dumps({k: (v if not isinstance(v, dict) else {kk: vv for kk, vv in v.items()
                                                            if kk in ("native_res", "count_positive")})
                      for k, v in summary.items()}, indent=2))


if __name__ == "__main__":
    main()
