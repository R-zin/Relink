"""Time-varying rainfall acquisition for CURRENT landslide-risk prediction.

Source: NASA POWER daily precipitation (PRECTOTCORR), regional endpoint.
  - spatial resolution : 0.5 deg (~55 km) native grid
  - temporal resolution: daily
  - units              : mm/day
  - coverage           : global, 1981 -> near-present (latency ~2-7 days;
                         unavailable days return the -999 fill value)
  - download           : HTTPS GET, no auth
    https://power.larc.nasa.gov/api/temporal/daily/regional

The 2018 baseline used a frozen Aug-2018 snapshot; this module makes rainfall
genuinely time-varying so risk can be predicted for a user-specified date
(default: the latest available day, i.e. "today" minus source latency).

Nothing here fabricates data: days the source has not published yet come back
as the -999 fill and are dropped, and `end_date` is rolled back to the latest
day with real coverage.
"""

from __future__ import annotations

from datetime import date, timedelta
from pathlib import Path

import httpx
import numpy as np
import rasterio
from rasterio.transform import from_origin

FILL = -999.0
SOURCE = "NASA POWER PRECTOTCORR (daily, 0.5 deg, mm/day)"
API = "https://power.larc.nasa.gov/api/temporal/daily/regional"


def _fetch_grid(lonmin: float, lonmax: float, latmin: float, latmax: float,
                start: date, end: date) -> tuple[list[date], dict[date, np.ndarray],
                                                 list[float], list[float]]:
    """Pull daily precip over a bbox -> (dates, {date: 2D grid}, lats, lons)."""
    url = (f"{API}?parameters=PRECTOTCORR&community=AG"
           f"&longitude-min={lonmin}&longitude-max={lonmax}"
           f"&latitude-min={latmin}&latitude-max={latmax}"
           f"&start={start:%Y%m%d}&end={end:%Y%m%d}&format=JSON")
    d = httpx.get(url, timeout=180).json()
    if "features" not in d:
        raise RuntimeError(f"NASA POWER error: {d.get('messages')}")
    cells = [(f["geometry"]["coordinates"][1], f["geometry"]["coordinates"][0],
              f["properties"]["parameter"]["PRECTOTCORR"]) for f in d["features"]]
    lats = sorted({c[0] for c in cells}, reverse=True)
    lons = sorted({c[1] for c in cells})
    days = sorted(cells[0][2].keys())
    grid = {day: np.full((len(lats), len(lons)), np.nan, "float32") for day in days}
    for lat, lon, series in cells:
        i, j = lats.index(lat), lons.index(lon)
        for day in days:
            v = series[day]
            grid[day][i, j] = np.nan if v == FILL else v
    dates = [date(int(x[:4]), int(x[4:6]), int(x[6:8])) for x in days]
    return dates, {date(int(k[:4]), int(k[4:6]), int(k[6:8])): grid[k] for k in days}, lats, lons


def acquire_current(region, end_date: date | None = None, lookback_days: int = 40,
                    out_subdir: str = "current") -> dict:
    """Download daily rainfall for [end-lookback, end], clip-fill missing tail,
    and write rain_YYYYMMDD.tif per VALID day under data/raw/<Region>/rainfall/<out_subdir>/.

    end_date=None -> today; rolled back to the latest day with real (non-fill)
    data. Returns a summary dict (also written as _meta.json).
    """
    if end_date is None:
        end_date = date.today()
    b = region.boundary_wgs84()
    minx, miny, maxx, maxy = [float(v) for v in b.total_bounds]
    # NASA POWER regional endpoint requires >= 2 deg span in each axis
    lonmin, lonmax = minx, max(minx + 2.0, maxx)
    latmin, latmax = miny, max(miny + 2.0, maxy)

    start = end_date - timedelta(days=lookback_days)
    dates, grids, lats, lons = _fetch_grid(lonmin, lonmax, latmin, latmax, start, end_date)

    # keep only days with at least one real observation
    valid_days = [d for d in dates if np.isfinite(grids[d]).any()]
    if not valid_days:
        raise RuntimeError("NASA POWER returned no usable days for the window")
    latest = max(valid_days)

    out_dir = region.raw_dir / "rainfall" / out_subdir
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in out_dir.glob("rain_*.tif"):
        f.unlink()
    res = abs(lats[0] - lats[1]) if len(lats) > 1 else 0.5
    tr = from_origin(lons[0] - res / 2, lats[0] + res / 2, res, res)
    written = []
    for d in valid_days:
        p = out_dir / f"rain_{d:%Y%m%d}.tif"
        with rasterio.open(p, "w", driver="GTiff", height=len(lats), width=len(lons),
                           count=1, dtype="float32", crs="EPSG:4326", transform=tr,
                           nodata=np.nan) as ds:
            ds.write(grids[d], 1)
        written.append(p.name)

    meta = {
        "source": SOURCE,
        "native_spatial_res": "0.5 deg (~55 km)",
        "temporal_res": "daily",
        "units": "mm/day",
        "requested_end_date": str(end_date),
        "latest_available_date": str(latest),
        "date_coverage": f"{min(valid_days)} .. {latest} ({len(valid_days)} days)",
        "download": "HTTPS GET NASA POWER regional endpoint, no auth",
        "files": written,
    }
    import json
    (out_dir / "_meta.json").write_text(json.dumps(meta, indent=2))
    return meta


if __name__ == "__main__":
    import argparse, json
    from region import Region
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", default="kerala")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD end/prediction date")
    ap.add_argument("--lookback", type=int, default=40)
    a = ap.parse_args()
    region = Region.from_config(a.region)
    end = date.fromisoformat(a.date) if a.date else None
    print(json.dumps(acquire_current(region, end, a.lookback), indent=2))
