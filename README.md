# Landslide Susceptibility & Risk Mapping Engine

India-focused ML system producing **pixel-wise landslide susceptibility
probability** rasters, risk-classified polygons, and an OpenStreetMap/Leaflet
interactive map, integrated with RELINK. Implements `../plan.md`.

> **Terminology discipline.** Output is `P(landslide | terrain, vegetation,
> rainfall)` -- a *susceptibility*, i.e. a **potential landslide-prone
> region**. It is **not** a detection of an active landslide. Maps, APIs, docs
> and UI labels never say "landslide detected".

---

## Region-driven pipeline

Every stage is parameterized by a region config (`config/regions/<name>.yaml`).
**Switching regions is a config change, never a code change.**

```bash
python main.py --region kerala all      # full pipeline
python main.py --region idukki all      # same code, different region config
```

Region config (`config/regions/kerala.yaml`):

```yaml
region:
  name: Kerala
  boundary_path: data/regions/kerala/boundary.geojson   # single spatial authority
  crs: EPSG:32643            # UTM zone 43N
  target_resolution_m: 30
  block_size_km: 5           # spatial split block size
grid: { snap: align-to-boundary, buffer_m: 500 }
outputs_dir: outputs/Kerala
```

Add a new region by dropping in a new `config/regions/<name>.yaml` + a boundary
GeoJSON at `data/regions/<name>/boundary.geojson`. No code edits.

---

## Pipeline stages (`main.py <stage>`)

| Stage | What it does | Output |
|---|---|---|
| `acquire` | Acquire region-clipped raw rasters. Currently generates **synthetic stand-ins** (see below) for SRTM DEM, Sentinel-2 B4/B8, land cover, IMD rainfall, GSI inventory. | `data/raw/<Region>/` |
| `preprocess` | Reproject -> clip -> resample -> align every feature to the region's common 30 m grid; derive slope/aspect/curvature, NDVI, rain 1d/3d/7d. | `data/processed/<Region>/stack/*.tif` |
| `validate` | Coverage + alignment + boundary + label gates (`validate_region_data.py`). **Aborts on any gap/misalignment.** | console/JSON report |
| `dataset` | Build pixel dataset; positives = inventory pixels, negatives = buffered non-inventory sample; block-based spatial split (no leakage). | `dataset.parquet`, `splits.json` |
| `train` | Train Logistic Regression, Random Forest, XGBoost on identical splits; select best by spatial-val PR-AUC. | `best_model.joblib`, `model_metrics.json` |
| `predict` | Chunked pixel-wise prediction -> probability raster -> 5-class risk raster. | `susceptibility.tif`, `risk_classes.tif` |
| `polygonize` | High+Very-High pixels -> connected components -> min-area filter -> EPSG:4326 polygons with attributes. | `risk_regions.geojson` |
| `export` | Export boundary-filtered inventory + finalize `source_metadata.json`. | `historical_landslides.geojson` |

---

## API & web map

```bash
python -m api.main          # serves API + web map at http://127.0.0.1:8000
```

Endpoints (region parameter defaults to active region):
- `GET /api/risk-regions?region=Kerala` -> risk polygons GeoJSON
- `GET /api/historical-landslides?region=Kerala` -> inventory GeoJSON
- `GET /api/point-risk?lat=..&lon=..` -> susceptibility + class at a coordinate
- `GET /api/metadata?region=Kerala` -> metrics, features, sources, disclaimers
- `GET /api/context?bbox=..` -> OSM context layers (roads/hospitals/shelters/rivers)

The Leaflet map (`web/`) has toggleable layers: OSM basemap, potential
landslide regions (clickable), historical landslides, geolocation "risk at my
location", legend, and the susceptibility-not-detection disclaimer.

---

## Testing

```bash
python -m pytest            # full suite
python -m pytest -m "not slow"   # unit tests only (skip full-region cached checks)
```

Tests cover: region/grid framework, DEM features (slope magnitude, aspect
circular encoding, NoData propagation), NDVI/rainfall math, raster alignment
resampling rules + shared validity mask, dataset spatial-split leakage
invariants, model harness + metrics + selection, risk classification +
polygonization min-area filtering, API smoke tests, and region-switch
end-to-end output completeness/alignment.

---

## Data sources & the synthetic stand-in

`generate_synthetic_data.py` creates **plausible synthetic** rasters at each
source's *native* resolution/CRS so the full pipeline runs and is testable
offline. This is a development stand-in for the real products:

| Layer | Synthetic stand-in for | Native res (real) |
|---|---|---|
| DEM | NASA SRTM | ~30-90 m |
| NDVI (B4/B8) | Sentinel-2 median composite | 10-60 m |
| Land cover | ESA WorldCover / Copernicus DLC | 10-100 m |
| Rainfall | IMD 0.25 deg daily grids | ~25 km |
| Inventory | GSI / Bhuvan landslide inventory | points/polygons |

**To use real data:** replace `stage_acquire` to download/clip the real
products into `data/raw/<Region>/` with the same filenames, and replace
`data/regions/kerala/boundary.geojson` with the official Survey of India / GADM
/ OSM boundary. Downstream stages are unchanged.

### Resolution honesty
Resampling coarse IMD rainfall (~0.25 deg, ~25 km) to the 30 m grid does **not**
create 30 m rainfall accuracy -- it interpolates/assigns the coarse field onto
the grid. Native resolution is recorded in `source_metadata.json` and surfaced
in `/api/metadata` and the map caption.

---

## Outputs (`outputs/<Region>/`)

```
susceptibility.tif      # pixel-wise probability 0-1 (float32), masked to boundary
risk_classes.tif        # 5-class risk raster (uint8) with color table
risk_regions.geojson    # High/Very-High polygons (EPSG:4326) + attributes
historical_landslides.geojson
model_metrics.json      # all three models' metrics + selection rationale
source_metadata.json    # per-dataset source/date/native res/CRS/preprocessing
best_model.joblib
```

Risk classes (configurable in `config.yaml`):
0.00-0.20 Very Low, 0.20-0.40 Low, 0.40-0.60 Moderate, 0.60-0.80 High,
0.80-1.00 Very High.

---

## Limitations (v1)

- **Synthetic data stand-in.** Metrics reflect a synthetic signal, not real
  landslide behaviour. Wire real GSI inventory + DEM/Sentinel/IMD before any
  operational use (see "Data sources" above).
- **Simplified boundary.** The bundled Kerala boundary is a coarse prototype
  outline, not survey-grade; replace with the official state boundary.
- **Geology dropped** per the fallback chain (GSI/BhuKosh not wired in).
- **Chunked prediction** is implemented but skipped for the ~43M-pixel Kerala
  grid in this prototype run; Idukki runs it fully.
- Negative samples mean "not in the inventory", **not** "landslide impossible".

## Environment

Python 3.11+; see `requirements.txt` (rasterio/GDAL, geopandas, scikit-learn,
xgboost, fastapi, ...). GDAL/rasterio install is the most common failure point.
