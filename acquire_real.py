"""Real data acquisition (plan.md Phase 1).

Downloads region-clipped real rasters into data/raw/<Region>/ with the SAME
filenames the synthetic stand-in used, so every downstream stage is unchanged.

Real sources and their status:
  DEM       AWS elevation-tiles (Terrarium encoding, Mapzen/SRTM-derived).
            Mosaicked per region, decoded to metres, clipped to AOI. WORKS offline-ish.
  Rainfall  NASA GPM IMERG daily (GES DISC). Requires Earthdata login
            (earthaccess). Optional; falls back with a clear note.
  NDVI      Sentinel-2 B4/B8 via Copernicus/SentinelHub. Requires credentials.
            Falls back with a clear note.
  Landcover ESA WorldCover 2021 tiles (public AWS). Real download attempted.
  Inventory Real open landslide inventories are tried (NASA GLC); on failure a
            clear message explains how to place a GSI/Bhuvan CSV/GeoJSON at
            data/raw/<Region>/landslides/inventory.geojson.

The pipeline never fabricates data: any source that cannot be acquired is
reported, and the caller decides whether to drop the feature (geology) or stop
(inventory -- supervised learning is impossible without it, plan.md Phase 1
go/no-go gate).
"""

from __future__ import annotations

import argparse
import io
import json
import math
import time
from pathlib import Path

import geopandas as gpd
import httpx
import numpy as np
import rasterio
from affine import Affine
from pyproj import Transformer
from rasterio.crs import CRS
from rasterio.merge import merge
from rasterio.warp import Resampling, reproject
from shapely.geometry import Point

from region import Region, load_global_config

ELEV_TILE = "https://s3.amazonaws.com/elevation-tiles-prod/geotiff/{z}/{x}/{y}.tif"
# ESA WorldCover 2021 v200 public tiles (3x3 deg, EPSG:4326, 10 m)
ESA_WC = ("https://esa-worldcover.s3.eu-central-1.amazonaws.com/"
          "v200/2021/map/ESA_WorldCover_10m_2021_v200_{ns}{lat:02d}{ew}{lon:03d}_Map.tif")

TIMEOUT = httpx.Timeout(60.0, connect=30.0)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def _lonlat_to_tile(lon: float, lat: float, z: int) -> tuple[int, int]:
    n = 2 ** z
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return x, y


def _terrarium_to_meters(arr: np.ndarray) -> np.ndarray:
    """Terrarium PNG/GeoTIFF encoding -> metres (float32)."""
    a = arr.astype(np.float32)
    # elevation-tiles geotiff stores raw 16-bit values already decoded to the
    # terrarium integer: elev = value * (1/256) ... but rasterio gives us int16
    # where the encoded formula is: h = (R*256 + G + B/256) - 32768 packed.
    # For the geotiff product the stored value is already (h+32768)*256 >> 8
    # scale; empirically the int16 reads as metres*256 offset - we decode:
    return (a - 32768.0) / 256.0 if a.max() > 10000 else a


# ---------------------------------------------------------------------------
# DEM: real elevation-tile mosaic for the region bbox
# ---------------------------------------------------------------------------
def acquire_dem(region: Region, zoom: int = 9) -> dict:
    """Download real SRTM-derived elevation tiles covering the region bbox,
    mosaic, reproject to EPSG:4326 metres, clip to bbox (region clip happens in
    preprocess). zoom=9 (~600 m tiles) keeps tile count reasonable; preprocess
    resamples to the 30 m grid (documented upsampling, native ~600 m at z9).
    Use zoom=11-12 for finer native DEM if bandwidth allows."""
    b = region.boundary_wgs84()
    minx, miny, maxx, maxy = b.total_bounds
    x0, y1 = _lonlat_to_tile(minx, miny, zoom)
    x1, y0 = _lonlat_to_tile(maxx, maxy, zoom)
    xs = range(min(x0, x1), max(x0, x1) + 1)
    ys = range(min(y0, y1), max(y0, y1) + 1)

    tiles = []
    with httpx.Client(timeout=TIMEOUT, follow_redirects=True) as client:
        for x in xs:
            for y in ys:
                url = ELEV_TILE.format(z=zoom, x=x, y=y)
                try:
                    r = client.get(url)
                    if r.status_code != 200:
                        continue
                    with rasterio.open(io.BytesIO(r.content)) as src:
                        arr = src.read(1)
                        tiles.append((arr, src.transform, src.crs, src.nodata))
                except Exception:
                    continue
    if not tiles:
        raise RuntimeError("no elevation tiles downloaded for region bbox")

    # decode terrarium -> metres and mosaic in EPSG:3857, then reproject to 4326
    mems = []
    for arr, tr, crs, nodata in tiles:
        m = _terrarium_to_meters(arr)
        mem = rasterio.io.MemoryFile()
        with mem.open(driver="GTiff", height=m.shape[0], width=m.shape[1], count=1,
                      dtype="float32", crs=crs, transform=tr, nodata=np.nan) as ds:
            ds.write(m.astype(np.float32), 1)
        mems.append(mem.open())
    mosaic, mtr = merge(mems)
    for d in mems:
        d.close()

    # reproject mosaic to EPSG:4326
    dst_crs = CRS.from_epsg(4326)
    tr_wgs, w, h = rasterio.warp.calculate_default_transform(
        mems[0].crs if mems else CRS.from_epsg(3857), dst_crs,
        mosaic.shape[2], mosaic.shape[1], *mems_bounds(mosaic, mtr))
    out = np.full((h, w), np.nan, dtype=np.float32)
    reproject(source=mosaic[0], destination=out,
              src_transform=mtr, src_crs=CRS.from_epsg(3857), src_nodata=np.nan,
              dst_transform=tr_wgs, dst_crs=dst_crs, dst_nodata=np.nan,
              resampling=Resampling.bilinear)

    out_path = region.raw_dir / "dem" / "dem_raw.tif"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with rasterio.open(out_path, "w", driver="GTiff", height=h, width=w, count=1,
                       dtype="float32", crs=dst_crs, transform=tr_wgs,
                       nodata=np.nan, compress="deflate") as ds:
        ds.write(out, 1)
    return {
        "path": str(out_path), "source": "AWS elevation-tiles (Terrarium, SRTM-derived)",
        "native_res": f"~{600 if zoom==9 else 30*(2**(9-zoom)) if zoom<=9 else 30} m (z{zoom})",
        "native_crs": "EPSG:4326", "tiles": len(tiles),
    }


def mems_bounds(mosaic, mtr):
    h, w = mosaic.shape[1], mosaic.shape[2]
    left, top = mtr.c, mtr.f
    right, bottom = left + w * mtr.a, top + h * mtr.e
    return left, bottom, right, top


# ---------------------------------------------------------------------------
# Rainfall: NASA GPM IMERG daily via earthaccess (optional)
# ---------------------------------------------------------------------------
def acquire_rainfall(region: Region, days: int = 14) -> dict:
    """Download real GPM IMERG daily precipitation clipped to the region bbox.
    Requires NASA Earthdata login via `earthaccess`. If unavailable, returns a
    status dict explaining the fallback (plan.md: GPM/IMD merged -> ERA5-Land)."""
    try:
        import earthaccess  # type: ignore
    except ImportError:
        return {"status": "fallback",
                "note": "earthaccess not installed; GPM IMERG requires NASA Earthdata "
                        "login. `pip install earthaccess` and set EARTHDATA credentials, "
                        "or place IMD/ERA5 daily NetCDFs in data/raw/<Region>/rainfall/. "
                        "Falling back per plan.md Section 12 (IMD access friction)."}
    b = region.boundary_wgs84()
    minx, miny, maxx, maxy = b.total_bounds
    try:
        earthaccess.login()
        results = earthaccess.search_data(
            short_name="GPM_3IMERGDF", version="07",
            bounding_box=(minx, miny, maxx, maxy), count=days)
        files = earthaccess.download(results, str(region.raw_dir / "rainfall" / "_nc"))
    except Exception as exc:
        return {"status": "fallback", "note": f"IMERG download failed: {exc}. "
                "Place daily rainfall grids in data/raw/<Region>/rainfall/."}
    return {"status": "ok", "files": [str(f) for f in files],
            "source": "NASA GPM IMERG daily v07", "native_res": "0.1 deg (~11 km)"}


# ---------------------------------------------------------------------------
# Land cover: ESA WorldCover 2021 public tiles
# ---------------------------------------------------------------------------
def acquire_landcover(region: Region) -> dict:
    """Download real ESA WorldCover 2021 10 m tiles covering the region bbox."""
    b = region.boundary_wgs84()
    minx, miny, maxx, maxy = b.total_bounds
    lats = range(int(math.floor(miny / 3) * 3), int(math.ceil(maxy / 3) * 3) + 1, 3)
    lons = range(int(math.floor(minx / 3) * 3), int(math.ceil(maxx / 3) * 3) + 1, 3)
    out_dir = region.raw_dir / "landcover"
    out_dir.mkdir(parents=True, exist_ok=True)
    downloaded = []
    with httpx.Client(timeout=TIMEOUT, follow_redirects=True) as client:
        for lat in lats:
            for lon in lons:
                ns = "N" if lat >= 0 else "S"
                ew = "E" if lon >= 0 else "W"
                url = ESA_WC.format(lat=abs(lat), ns=ns, lon=abs(lon), ew=ew)
                try:
                    r = client.get(url)
                    if r.status_code == 200 and len(r.content) > 1000:
                        p = out_dir / f"wc_{lat}_{lon}.tif"
                        p.write_bytes(r.content)
                        downloaded.append(p)
                except Exception:
                    continue
    if not downloaded:
        return {"status": "fallback",
                "note": "ESA WorldCover tiles not downloaded (network/URL). "
                        "Place WorldCover GeoTIFFs in data/raw/<Region>/landcover/."}
    # mosaic to landcover_raw.tif (nearest, categorical)
    srcs = [rasterio.open(p) for p in downloaded]
    mosaic, mtr = merge(srcs)
    profile = srcs[0].profile.copy()
    for s in srcs:
        s.close()
    profile.update(height=mosaic.shape[1], width=mosaic.shape[2], transform=mtr,
                   compress="deflate")
    out_path = out_dir / "landcover_raw.tif"
    with rasterio.open(out_path, "w", **profile) as ds:
        ds.write(mosaic)
    return {"status": "ok", "path": str(out_path),
            "source": "ESA WorldCover 2021 v200", "native_res": "10 m",
            "native_crs": "EPSG:4326", "tiles": len(downloaded), "note": "categorical"}


# ---------------------------------------------------------------------------
# Landslide inventory: real open sources, else documented manual path
# ---------------------------------------------------------------------------
def acquire_inventory(region: Region) -> dict:
    """Try real open landslide inventories clipped to the region boundary.
    On failure, explain how to supply a GSI/Bhuvan inventory manually."""
    b = region.boundary_wgs84()
    union = b.union_all()
    minx, miny, maxx, maxy = b.total_bounds

    # candidate real sources (open). NASA GLC ArcGIS is frequently slow/blocked.
    candidates = [
        ("NASA Global Landslide Catalog",
         "https://maps.nccs.nasa.gov/arcgis/rest/services/landslide/MapServer/0/query"
         f"?geometry={minx},{miny},{maxx},{maxy}&geometryType=esriGeometryEnvelope"
         "&inSR=4326&spatialRel=esriSpatialRelIntersects&outFields=*&f=geojson"),
    ]
    for name, url in candidates:
        try:
            with httpx.Client(timeout=httpx.Timeout(45.0, connect=20.0),
                              follow_redirects=True) as client:
                r = client.get(url)
            if r.status_code == 200 and "FeatureCollection" in r.text[:200]:
                gdf = gpd.read_file(io.BytesIO(r.content))
                gdf = gdf[gdf.geometry.within(union)]
                if len(gdf) > 0:
                    out = region.raw_dir / "landslides" / "inventory.geojson"
                    out.parent.mkdir(parents=True, exist_ok=True)
                    gdf.to_file(out, driver="GeoJSON")
                    return {"status": "ok", "source": name, "count_positive": len(gdf),
                            "path": str(out)}
        except Exception:
            continue

    # check for a manually-placed inventory
    manual = region.raw_dir / "landslides" / "inventory.geojson"
    if manual.exists():
        gdf = gpd.read_file(manual)
        return {"status": "manual", "source": "user-supplied (GSI/Bhuvan)",
                "count_positive": len(gdf), "path": str(manual)}
    return {
        "status": "missing",
        "note": ("No real inventory acquired. Supervised learning requires one. "
                 "Download the GSI/Bhuvan landslide inventory (or a published Kerala "
                 "2018/2019 event inventory) and save it as "
                 "data/raw/<Region>/landslides/inventory.geojson with point/polygon "
                 "geometries in EPSG:4326. Then re-run `acquire` and downstream."),
    }


# ---------------------------------------------------------------------------
# NDVI: Sentinel-2 requires credentials -> documented fallback
# ---------------------------------------------------------------------------
def acquire_ndvi(region: Region) -> dict:
    return {
        "status": "fallback",
        "note": ("Sentinel-2 B4/B8 requires Copernicus Data Space / SentinelHub "
                 "credentials. Configure credentials and implement a low-cloud median "
                 "composite, or export a Kerala NDVI composite from Google Earth Engine "
                 "to data/raw/<Region>/sentinel/b04_red.tif and b08_nir.tif."),
    }


# ---------------------------------------------------------------------------
# orchestration
# ---------------------------------------------------------------------------
def acquire_all(region: Region, global_cfg: dict, dem_zoom: int = 9,
                rainfall_days: int = 14) -> dict:
    region.ensure_dirs()
    results = {}
    results["dem"] = acquire_dem(region, zoom=dem_zoom)
    results["landcover"] = acquire_landcover(region)
    results["rainfall"] = acquire_rainfall(region, days=rainfall_days)
    results["ndvi"] = acquire_ndvi(region)
    results["landslides"] = acquire_inventory(region)

    # record whatever succeeded into source_metadata.json
    for key, entry in results.items():
        if isinstance(entry, dict):
            region.record_source(key, entry)
    return results


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Real data acquisition")
    ap.add_argument("--region", default="kerala")
    ap.add_argument("--dem-zoom", type=int, default=9)
    ap.add_argument("--rainfall-days", type=int, default=14)
    args = ap.parse_args(argv)
    region = Region.from_config(args.region)
    cfg = load_global_config()
    results = acquire_all(region, cfg, dem_zoom=args.dem_zoom,
                          rainfall_days=args.rainfall_days)
    print(json.dumps(results, indent=2, default=str))
    missing = [k for k, v in results.items()
               if isinstance(v, dict) and v.get("status") in ("missing", "fallback")]
    print(f"\nAcquired-with-real-data: "
          f"{[k for k,v in results.items() if isinstance(v,dict) and v.get('status') in ('ok','manual')]}")
    print(f"Fallback/manual needed: {missing}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
