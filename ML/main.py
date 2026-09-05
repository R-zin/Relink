"""Region-driven pipeline entry point (plan.md 2.4 / DoD 5).

Usage:
    python main.py --region kerala all
    python main.py --region kerala acquire preprocess dataset train predict polygonize export
    python main.py --region idukki all        # region switch = config only

Stages operate only within the region boundary; all artifacts go to
outputs/<RegionName>/.
"""

from __future__ import annotations

import argparse
import json
import sys

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio

from region import Region, load_global_config


# ---------------------------------------------------------------------------
# Stage 1: acquire
# ---------------------------------------------------------------------------
def stage_acquire(region: Region, cfg: dict) -> dict:
    raw = region.raw_dir
    summary = raw / "synthetic_summary.json"
    dem = raw / "dem" / "dem_raw.tif"
    if not dem.exists():
        from generate_synthetic_data import generate
        print(f"[acquire] no raw data found for {region.name}; generating synthetic stand-ins")
        summary_data = generate(region, cfg)
    else:
        summary_data = json.loads(summary.read_text()) if summary.exists() else {}
        print(f"[acquire] using existing raw data in {raw}")
    region.ensure_dirs()
    for key, entry in summary_data.items():
        if isinstance(entry, dict) and "source" in entry:
            region.record_source(key, entry)
    return summary_data


# ---------------------------------------------------------------------------
# Stage 2: preprocess -> aligned feature stack on the common grid
# ---------------------------------------------------------------------------
def stage_preprocess(region: Region, cfg: dict) -> list[str]:
    from preprocessing.raster_align import align_to_grid, boundary_mask, resampling_for
    from preprocessing.dem_features import (
        aspect_sin_cos, slope_aspect_curvature, write_feature,
    )
    from preprocessing.ndvi import compute_ndvi
    from preprocessing.rainfall import accumulate, load_daily_series
    from rasterio.warp import reproject
    from rasterio.crs import CRS

    spec = region.grid_spec()
    boundary = region.boundary()
    stack = region.stack_dir
    stack.mkdir(parents=True, exist_ok=True)
    raw = region.raw_dir

    print(f"[preprocess] {region.describe()}")

    # DEM -> aligned, then derived features on the grid
    dem_al = align_to_grid(raw / "dem" / "dem_raw.tif", spec, stack / "elev.tif",
                           "elev", boundary)
    with rasterio.open(dem_al) as src:
        dem = src.read(1)
        nodata = src.nodata
    slope, aspect, curvature = slope_aspect_curvature(dem, spec["resolution"], nodata)
    a_sin, a_cos = aspect_sin_cos(aspect, nodata)
    write_feature(stack / "slope.tif", slope, spec)
    write_feature(stack / "curvature.tif", curvature, spec)
    write_feature(stack / "aspect_sin.tif", a_sin, spec)
    write_feature(stack / "aspect_cos.tif", a_cos, spec)

    # NDVI from aligned B4/B8
    red = align_to_grid(raw / "sentinel" / "b04_red.tif", spec, stack / "_red.tif",
                        "ndvi", boundary)
    nir = align_to_grid(raw / "sentinel" / "b08_nir.tif", spec, stack / "_nir.tif",
                        "ndvi", boundary)
    with rasterio.open(red) as s1, rasterio.open(nir) as s2:
        ndvi = compute_ndvi(s1.read(1), s2.read(1), nodata)
    write_feature(stack / "ndvi.tif", ndvi, spec)
    (stack / "_red.tif").unlink(missing_ok=True)
    (stack / "_nir.tif").unlink(missing_ok=True)

    # Land cover (categorical -> nearest)
    align_to_grid(raw / "landcover" / "landcover_raw.tif", spec, stack / "lulc.tif",
                  "lulc", boundary)

    # Rainfall accumulations from daily grids -> align each day, then accumulate
    dates, arrays, native_profile = load_daily_series(raw / "rainfall")

    h, w = spec["height"], spec["width"]
    big = h * w > 40_000_000  # large grids: stream accumulations to bound memory

    def align_native(arr, feature, dst=None):
        if dst is None:
            dst = np.full((h, w), -9999.0, dtype=np.float32)
        reproject(
            source=arr, destination=dst,
            src_transform=native_profile["transform"], src_crs=native_profile["crs"],
            src_nodata=native_profile["nodata"],
            dst_transform=spec["transform"], dst_crs=CRS.from_user_input(spec["crs"]),
            dst_nodata=-9999.0, resampling=resampling_for(feature),
        )
        dst[~boundary_mask(spec, boundary)] = -9999.0
        return dst

    if big:
        # stream: write each aligned day to a temp GeoTIFF, then read back only
        # the tail needed for each window. Bounds RAM to a couple of grids.
        inside = boundary_mask(spec, boundary)
        day_buf = np.full((h, w), -9999.0, dtype=np.float32)
        tmpdir = stack / "_rain_days"
        tmpdir.mkdir(exist_ok=True)
        day_files = []
        for i, a in enumerate(arrays):
            align_native(a, "rain_1d", dst=day_buf)
            f = tmpdir / f"day_{i:03d}.tif"
            write_feature(f, day_buf, spec)
            day_files.append(f)
        del day_buf
        for wd in (1, 3, 7):
            tail = []
            for f in day_files[-wd:]:
                with rasterio.open(f) as src:
                    tail.append(src.read(1))
            acc = accumulate(tail, wd)
            write_feature(stack / f"rain_{wd}d.tif", acc, spec)
            del tail
        for f in day_files:
            f.unlink(missing_ok=True)
        tmpdir.rmdir()
    else:
        aligned_days = [align_native(a, "rain_1d") for a in arrays]
        for window, name in ((1, "rain_1d"), (3, "rain_3d"), (7, "rain_7d")):
            acc = accumulate(aligned_days, window)
            write_feature(stack / f"{name}.tif", acc, spec)

    features = ["elev", "slope", "aspect_sin", "aspect_cos", "curvature",
                "ndvi", "lulc", "rain_1d", "rain_3d", "rain_7d"]
    print(f"[preprocess] stack written: {stack} ({len(features)} features)")
    return features


# ---------------------------------------------------------------------------
# Stage 2.5: validate coverage/alignment gates (plan.md 1A.5)
# ---------------------------------------------------------------------------
def stage_validate(region: Region, cfg: dict) -> dict:
    import validate_region_data
    report = validate_region_data.validate(region)
    validate_region_data.assert_valid(report)
    print(f"[validate] OK: {report['summary']}")
    return report


# ---------------------------------------------------------------------------
# Stage 3: dataset
# ---------------------------------------------------------------------------
def stage_dataset(region: Region, cfg: dict) -> pd.DataFrame:
    from preprocessing.raster_align import shared_validity_mask
    from preprocessing.dataset_builder import (
        block_grid, positives_mask, sample_negatives, build_dataset, FEATURE_COLUMNS,
    )

    spec = region.grid_spec()
    boundary = region.boundary()
    features = [c for c in FEATURE_COLUMNS if (region.stack_dir / f"{c}.tif").exists()]
    valid = shared_validity_mask(region.stack_dir, features, spec, boundary)

    inv_path = region.raw_dir / "landslides" / "inventory.geojson"
    inventory = gpd.read_file(inv_path)
    b = region.boundary_wgs84().union_all()
    inv_w = inventory.to_crs("EPSG:4326")
    inside = inv_w.geometry.within(b)
    dropped = int((~inside).sum())
    if dropped:
        print(f"[dataset] dropped {dropped} out-of-boundary inventory records")
    inventory = inventory[inside.values]

    pos = positives_mask(spec, boundary, inventory, cfg["dataset"]["pos_buffer_px"])
    n_pos = int(pos.sum())
    rng = np.random.default_rng(cfg["random_seed"])
    neg_buffer_px = int(round(cfg["dataset"]["neg_buffer_m"] / spec["resolution"]))
    neg = sample_negatives(valid, pos, n_pos * cfg["dataset"]["neg_pos_ratio"],
                           neg_buffer_px, rng)
    blocks = block_grid(spec, region.block_size_km)

    df = build_dataset(region.stack_dir, spec, valid, pos, neg, blocks,
                       cfg["dataset"]["split_fractions"], cfg["random_seed"])
    region.processed_dir.mkdir(parents=True, exist_ok=True)
    out = region.processed_dir / "dataset.parquet"
    df.to_parquet(out, index=False)
    splits = {
        "block_size_km": region.block_size_km,
        "n_blocks": int(df["block_id"].nunique()),
        "n_positives": n_pos,
        "neg_pos_ratio": cfg["dataset"]["neg_pos_ratio"],
        "note": "negatives mean 'not in inventory', not 'landslide impossible'",
    }
    with open(region.processed_dir / "splits.json", "w") as fh:
        json.dump(splits, fh, indent=2, default=str)
    print(f"[dataset] {len(df)} rows ({n_pos} positives) -> {out}")
    return df


# ---------------------------------------------------------------------------
# Stage 4: train + evaluate
# ---------------------------------------------------------------------------
def stage_train(region: Region, cfg: dict) -> dict:
    from models.train import (
        available_features, design_matrix, build_models, predict_proba, save_model,
    )
    from models.evaluate import classification_metrics, select_best

    df = pd.read_parquet(region.processed_dir / "dataset.parquet")
    cont, cat = available_features(df)
    feature_names = cont + cat
    X = design_matrix(df, cont, cat)
    y = df["label"].to_numpy()

    seed = cfg["random_seed"]
    models = build_models(cfg, seed)
    metrics = {}
    trained = {}
    for name, model in models.items():
        model.fit(X[df["split"] == "train"], y[df["split"] == "train"])
        trained[name] = model
        entry = {}
        for split in ("val", "test"):
            m = (df["split"] == split).to_numpy()
            if m.sum() == 0:
                continue
            prob = predict_proba(model, X[m])
            entry[split] = classification_metrics(y[m], prob)
        clf = model.named_steps.get("clf") if hasattr(model, "named_steps") else None
        if hasattr(clf, "feature_importances_"):
            entry["feature_importance"] = dict(
                zip(feature_names, [round(float(v), 4) for v in clf.feature_importances_])
            )
        metrics[name] = entry
        val = entry.get("val", {})
        print(f"[train] {name}: val PR-AUC={val.get('pr_auc')}, "
              f"ROC-AUC={val.get('roc_auc')}, F1={val.get('f1')}")

    best = select_best(metrics)
    region.ensure_dirs()
    save_model(trained[best], region.outputs_dir / "best_model.joblib", feature_names,
               {"best_model": best, "region": region.name, "seed": seed})
    out = {
        "region": region.name,
        "features": feature_names,
        "best_model": best,
        "selection": "max spatial-validation PR-AUC, tie-break ROC-AUC (plan.md 6.3)",
        "models": metrics,
    }
    with open(region.outputs_dir / "model_metrics.json", "w") as fh:
        json.dump(out, fh, indent=2)
    print(f"[train] best model: {best} -> {region.outputs_dir / 'best_model.joblib'}")
    return out


# ---------------------------------------------------------------------------
# Stage 5: predict + classify
# ---------------------------------------------------------------------------
def stage_predict(region: Region, cfg: dict) -> dict:
    from models.train import load_model
    from preprocessing.raster_align import shared_validity_mask
    from prediction.predict_raster import predict_susceptibility, classify_to_raster

    model, feature_names, meta = load_model(region.outputs_dir / "best_model.joblib")
    spec = region.grid_spec()
    boundary = region.boundary()
    valid = shared_validity_mask(region.stack_dir, feature_names, spec, boundary)
    cat = [f for f in feature_names if f == "lulc"]

    sus = region.outputs_dir / "susceptibility.tif"
    if sus.exists():
        print(f"[predict] reusing existing {sus.name}")
    else:
        sus = predict_susceptibility(
            model, feature_names, region.stack_dir, spec, valid,
            sus,
            block_rows=cfg["prediction"]["block_rows"], categorical=cat,
        )
    cls = classify_to_raster(sus, region.outputs_dir / "risk_classes.tif", spec,
                             cfg["risk_thresholds"])
    print(f"[predict] wrote {sus.name}, {cls.name}")
    return {"susceptibility": str(sus), "risk_classes": str(cls)}


# ---------------------------------------------------------------------------
# Stage 6: polygonize
# ---------------------------------------------------------------------------
def stage_polygonize(region: Region, cfg: dict) -> int:
    from prediction.polygonize import polygonize_high_risk

    gdf = polygonize_high_risk(
        region.outputs_dir / "susceptibility.tif",
        region.outputs_dir / "risk_classes.tif",
        cfg["polygonize"]["high_risk_classes"],
        cfg["polygonize"]["min_area_km2"],
        cfg["risk_thresholds"],
        region.outputs_dir / "risk_regions.geojson",
        cfg["polygonize"]["simplify_tolerance_m"],
    )
    print(f"[polygonize] {len(gdf)} high-risk polygons -> risk_regions.geojson")
    return len(gdf)


# ---------------------------------------------------------------------------
# Stage 6b: export historical inventory + finalize metadata
# ---------------------------------------------------------------------------
def stage_export(region: Region, cfg: dict) -> None:
    inv = gpd.read_file(region.raw_dir / "landslides" / "inventory.geojson")
    b = region.boundary_wgs84().union_all()
    inv_w = inv.to_crs("EPSG:4326")
    inv_w = inv_w[inv_w.geometry.within(b)]
    region.ensure_dirs()
    inv_w.to_file(region.outputs_dir / "historical_landslides.geojson", driver="GeoJSON")
    region.record_source("landslides", {
        "source": "GSI inventory (synthetic stand-in for prototype)",
        "count_positive": int(len(inv_w)),
        "date_range": "2018-08 (synthetic)",
        "note": "filtered to region boundary",
    })
    region.record_source("rainfall", {
        "source": "IMD gridded 0.25 deg (synthetic stand-in)",
        "native_res": "~25 km",
        "note": "resampled to 30 m grid; accuracy remains ~25 km",
    })
    print(f"[export] historical_landslides.geojson ({len(inv_w)} points) + metadata finalized")


STAGES = {
    "acquire": stage_acquire,
    "preprocess": stage_preprocess,
    "validate": stage_validate,
    "dataset": stage_dataset,
    "train": stage_train,
    "predict": stage_predict,
    "polygonize": stage_polygonize,
    "export": stage_export,
}
ALL = ["acquire", "preprocess", "validate", "dataset", "train", "predict",
       "polygonize", "export"]


def main(argv=None):
    ap = argparse.ArgumentParser(description="Landslide susceptibility pipeline")
    ap.add_argument("--region", default="kerala",
                    help="region name (config/regions/<name>.yaml) or path to a config")
    ap.add_argument("stages", nargs="*", default=["all"],
                    help=f"stages to run, or 'all' ({', '.join(ALL)})")
    args = ap.parse_args(argv)

    region = Region.from_config(args.region)
    cfg = load_global_config()
    region.ensure_dirs()

    stages = ALL if (not args.stages or args.stages == ["all"] or "all" in args.stages) else args.stages
    for s in stages:
        fn = STAGES.get(s)
        if fn is None:
            print(f"unknown stage: {s} (choose from {list(STAGES)})", file=sys.stderr)
            sys.exit(2)
        print(f"\n=== [{region.name}] stage: {s} ===")
        fn(region, cfg)
    print(f"\nDone. Outputs in {region.outputs_dir}")


if __name__ == "__main__":
    main()
