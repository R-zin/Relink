"""Coverage & alignment validation gates (plan.md 1A.5).

Runs before dataset construction; any failure aborts the pipeline with a
clear report -- never train on partially-covering or misaligned data.

Checks:
  1. Coverage: each feature raster fully covers the region boundary.
  2. Alignment: all rasters share identical CRS, transform, width, height.
  3. Boundary sanity: boundary reprojects cleanly; grid extent contains it.
  4. Label coverage: inventory points fall within the boundary.
"""

from __future__ import annotations

import argparse
import json
import sys

import geopandas as gpd
import numpy as np
import rasterio

from region import Region
from preprocessing.raster_align import boundary_mask

STACK_FEATURES = ["elev", "slope", "aspect_sin", "aspect_cos", "curvature",
                  "ndvi", "lulc", "rain_1d", "rain_3d", "rain_7d"]


class ValidationError(RuntimeError):
    """Raised when a region data validation gate fails."""


def validate(region: Region) -> dict:
    spec = region.grid_spec()
    report = {"region": region.name, "checks": {}, "failures": []}

    # --- check 3: boundary sanity -------------------------------------------
    try:
        boundary = region.boundary()  # reprojects to grid CRS
        minx, miny, maxx, maxy = boundary.total_bounds
        gx0, gy0, gx1, gy1 = spec["bounds"]
        res = spec["resolution"]
        contains = (gx0 <= minx + res and gy0 <= miny + res
                    and gx1 >= maxx - res and gy1 >= maxy - res)
        report["checks"]["boundary_sanity"] = {
            "ok": bool(contains),
            "boundary_bounds": [float(v) for v in (minx, miny, maxx, maxy)],
            "grid_bounds": [float(v) for v in spec["bounds"]],
        }
        if not contains:
            report["failures"].append("boundary_sanity: grid extent does not contain boundary")
    except Exception as exc:  # boundary reprojection failure
        report["checks"]["boundary_sanity"] = {"ok": False, "error": str(exc)}
        report["failures"].append(f"boundary_sanity: {exc}")
        return _finalize(report)

    inside = boundary_mask(spec, boundary)
    n_inside = int(inside.sum())

    # --- checks 1 & 2: coverage + alignment ----------------------------------
    ref = None
    align_fail, cover_fail = [], []
    feature_reports = {}
    for name in STACK_FEATURES:
        path = region.stack_dir / f"{name}.tif"
        if not path.exists():
            align_fail.append(f"{name}: missing {path.name}")
            continue
        with rasterio.open(path) as src:
            sig = (str(src.crs), tuple(src.transform), src.width, src.height)
            if ref is None:
                ref = sig
            elif sig != ref:
                align_fail.append(f"{name}: CRS/transform/size mismatch")
            arr = src.read(1)
            nodata = src.nodata
        if nodata is not None:
            valid = np.isfinite(arr) & (arr != nodata)
        else:
            valid = np.isfinite(arr)
        covered = valid[inside]
        frac = float(covered.mean()) if n_inside else 0.0
        feature_reports[name] = {"coverage_fraction": round(frac, 6)}
        if frac < 0.999:  # allow sub-pixel edge effects only
            cover_fail.append(f"{name}: covers {frac:.4%} of boundary (<99.9%)")

    report["checks"]["alignment"] = {
        "ok": not align_fail,
        "reference": {"crs": ref[0], "width": ref[2], "height": ref[3]} if ref else None,
        "features": list(feature_reports),
    }
    report["checks"]["coverage"] = {"ok": not cover_fail, "features": feature_reports}
    report["failures"].extend(f"alignment: {m}" for m in align_fail)
    report["failures"].extend(f"coverage: {m}" for m in cover_fail)

    # --- check 4: label coverage ---------------------------------------------
    inv_path = region.raw_dir / "landslides" / "inventory.geojson"
    if inv_path.exists():
        inv = gpd.read_file(inv_path).to_crs("EPSG:4326")
        b = region.boundary_wgs84().union_all()
        inside_inv = inv.geometry.within(b)
        report["checks"]["label_coverage"] = {
            "ok": True,
            "total": int(len(inv)),
            "inside": int(inside_inv.sum()),
            "dropped_out_of_boundary": int((~inside_inv).sum()),
        }
    else:
        report["checks"]["label_coverage"] = {"ok": False, "error": f"missing {inv_path}"}
        report["failures"].append("label_coverage: inventory file missing")

    return _finalize(report)


def _finalize(report: dict) -> dict:
    report["ok"] = not report["failures"]
    report["summary"] = ("all gates passed" if report["ok"]
                         else f"{len(report['failures'])} gate failure(s)")
    return report


def assert_valid(report: dict) -> None:
    if not report["ok"]:
        lines = "\n  - ".join(report["failures"])
        raise ValidationError(
            f"Region data validation failed for {report['region']}:\n  - {lines}\n"
            "Pipeline aborted: never train on partially-covering or misaligned data."
        )


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", default="kerala")
    args = ap.parse_args(argv)
    region = Region.from_config(args.region)
    report = validate(region)
    print(json.dumps(report, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
