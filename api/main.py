"""FastAPI backend serving region outputs (plan.md 9.1).

Terminology discipline: all text uses "potential landslide-prone region",
never "landslide detected". Native rainfall resolution caveats are surfaced
via /api/metadata.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import rasterio
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pyproj import Transformer

from region import PROJECT_ROOT, Region, load_global_config
from prediction.classify_risk import classify, class_name

app = FastAPI(title="Landslide Susceptibility API", version="0.1.0")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)

_GLOBAL_CFG = load_global_config()
DISCLAIMER = _GLOBAL_CFG.get(
    "disclaimer",
    "Susceptibility indicates where landslides are more likely; it is not a "
    "detection of an active event.",
)


def _region(region: str) -> Region:
    try:
        return Region.from_config(region)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))


def _output_file(reg: Region, name: str) -> Path:
    p = reg.outputs_dir / name
    if not p.exists():
        raise HTTPException(status_code=404,
                            detail=f"{name} not found for region {reg.name}. "
                                   "Run the pipeline first (main.py --region ...).")
    return p


@app.get("/api/risk-regions")
def risk_regions(region: str = Query("kerala")):
    reg = _region(region)
    return json.loads(_output_file(reg, "risk_regions.geojson").read_text(encoding="utf-8"))


@app.get("/api/historical-landslides")
def historical_landslides(region: str = Query("kerala")):
    reg = _region(region)
    return json.loads(_output_file(reg, "historical_landslides.geojson").read_text(encoding="utf-8"))


@app.get("/api/point-risk")
def point_risk(lat: float, lon: float, region: str = Query("kerala")):
    """Sampled susceptibility value + class at a coordinate."""
    reg = _region(region)
    sus = _output_file(reg, "susceptibility.tif")
    with rasterio.open(sus) as src:
        transformer = Transformer.from_crs("EPSG:4326", src.crs, always_xy=True)
        x, y = transformer.transform(lon, lat)
        row, col = src.index(x, y)
        if row < 0 or col < 0 or row >= src.height or col >= src.width:
            return {"in_region": False, "message": "coordinate outside grid",
                    "disclaimer": DISCLAIMER}
        val = float(src.read(1)[row, col])
        nodata = src.nodata
    if nodata is not None and val == nodata or not np.isfinite(val):
        return {"in_region": False, "message": "coordinate masked (outside boundary or NoData)",
                "disclaimer": DISCLAIMER}
    cls = int(classify(np.array([[val]]), _GLOBAL_CFG["risk_thresholds"])[0, 0])
    return {
        "in_region": True,
        "lat": lat,
        "lon": lon,
        "susceptibility": round(val, 4),
        "risk_class": cls,
        "risk_name": class_name(cls, _GLOBAL_CFG["risk_thresholds"]),
        "wording": "potential landslide-prone region",
        "disclaimer": DISCLAIMER,
    }


@app.get("/api/metadata")
def metadata(region: str = Query("kerala")):
    reg = _region(region)
    meta_path = _output_file(reg, "source_metadata.json")
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    metrics_path = reg.outputs_dir / "model_metrics.json"
    metrics = json.loads(metrics_path.read_text(encoding="utf-8")) if metrics_path.exists() else None
    return {
        "region": reg.name,
        "crs": reg.crs,
        "target_resolution_m": reg.target_resolution_m,
        "feature_list": _GLOBAL_CFG["features"],
        "risk_thresholds": _GLOBAL_CFG["risk_thresholds"],
        "rainfall_resolution_note": (
            "Native IMD rainfall is ~0.25 deg (~25 km); resampling to the 30 m "
            "grid interpolates the coarse field and does NOT create 30 m accuracy."
        ),
        "sources": meta,
        "model_metrics": metrics,
        "disclaimer": DISCLAIMER,
    }


@app.get("/api/context")
def context(bbox: str = Query(..., description="minx,miny,maxx,maxy in EPSG:4326")):
    """OSM context layers (roads/hospitals/shelters/rivers). Placeholder until
    Overpass extracts are cached; returns empty FeatureCollection with a note."""
    return {
        "type": "FeatureCollection",
        "features": [],
        "note": "context layer placeholder -- populate from cached OSM/Overpass extracts",
        "bbox": bbox,
    }


# ---- static frontend -------------------------------------------------------
web_dir = PROJECT_ROOT / "web"
if web_dir.exists():
    app.mount("/", StaticFiles(directory=web_dir, html=True), name="web")


def main():
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8000)


if __name__ == "__main__":
    main()
