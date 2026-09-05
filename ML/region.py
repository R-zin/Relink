"""Region/AOI framework (plan.md 1A).

All pipeline stages load a Region from config/regions/<name>.yaml and operate
only within the region boundary. Switching regions is a config change, never
a code change.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import geopandas as gpd
import rasterio
import yaml
from affine import Affine
from pyproj import CRS
from shapely.geometry import box

PROJECT_ROOT = Path(__file__).resolve().parent


def load_global_config(path: str | Path | None = None) -> dict:
    path = Path(path) if path else PROJECT_ROOT / "config.yaml"
    with open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


@dataclass
class Region:
    """A configured region/AOI."""

    name: str
    boundary_path: Path
    crs: str
    target_resolution_m: float
    block_size_km: float
    outputs_dir: Path
    grid_buffer_m: float = 500.0
    config: dict = field(default_factory=dict)
    project_root: Path = PROJECT_ROOT

    # ------------------------------------------------------------------ i/o
    @classmethod
    def from_config(cls, name_or_path: str, project_root: Path | None = None) -> "Region":
        """Load a region from a name (config/regions/<name>.yaml) or a YAML path."""
        root = Path(project_root) if project_root else PROJECT_ROOT
        candidate = Path(name_or_path)
        if not candidate.suffix:
            candidate = root / "config" / "regions" / f"{name_or_path}.yaml"
        elif not candidate.is_absolute():
            candidate = root / candidate
        if not candidate.exists():
            raise FileNotFoundError(f"Region config not found: {candidate}")
        with open(candidate, "r", encoding="utf-8") as fh:
            cfg = yaml.safe_load(fh)
        r = cfg["region"]
        return cls(
            name=r["name"],
            boundary_path=root / r["boundary_path"],
            crs=r["crs"],
            target_resolution_m=float(r.get("target_resolution_m", 30)),
            block_size_km=float(r.get("block_size_km", 5)),
            outputs_dir=root / cfg.get("outputs_dir", f"outputs/{r['name']}"),
            grid_buffer_m=float(cfg.get("grid", {}).get("buffer_m", 500)),
            config=cfg,
            project_root=root,
        )

    # ------------------------------------------------------------- boundary
    def boundary(self, crs: str | CRS | None = None) -> gpd.GeoDataFrame:
        """Region boundary reprojected to the requested CRS (default: grid CRS)."""
        if not self.boundary_path.exists():
            raise FileNotFoundError(
                f"Boundary file missing: {self.boundary_path}. "
                "Place the official boundary GeoJSON at data/regions/<region>/boundary.geojson"
            )
        gdf = gpd.read_file(self.boundary_path)
        if gdf.empty:
            raise ValueError(f"Boundary file {self.boundary_path} contains no features")
        target = CRS.from_user_input(crs) if crs else CRS.from_user_input(self.crs)
        if gdf.crs is None:
            gdf = gdf.set_crs("EPSG:4326")
        return gdf.to_crs(target)

    def boundary_wgs84(self) -> gpd.GeoDataFrame:
        return self.boundary("EPSG:4326")

    # ------------------------------------------------------------------ grid
    def grid_spec(self) -> dict:
        """Common prediction grid derived from the boundary extent + buffer.

        Returns dict with crs, transform, width, height, resolution.
        """
        b = self.boundary()  # in grid CRS
        minx, miny, maxx, maxy = b.total_bounds
        res = self.target_resolution_m
        buf = self.grid_buffer_m
        # snap outward to whole pixels
        import math

        minx = math.floor((minx - buf) / res) * res
        miny = math.floor((miny - buf) / res) * res
        maxx = math.ceil((maxx + buf) / res) * res
        maxy = math.ceil((maxy + buf) / res) * res
        width = int(round((maxx - minx) / res))
        height = int(round((maxy - miny) / res))
        transform = Affine(res, 0.0, minx, 0.0, -res, maxy)
        return {
            "crs": str(self.crs),
            "transform": transform,
            "width": width,
            "height": height,
            "resolution": res,
            "bounds": (minx, miny, maxx, maxy),
        }

    def grid_extent_polygon(self):
        minx, miny, maxx, maxy = self.grid_spec()["bounds"]
        return box(minx, miny, maxx, maxy)

    # ------------------------------------------------------------------ io
    @property
    def processed_dir(self) -> Path:
        return self.project_root / "data" / "processed" / self.name

    @property
    def stack_dir(self) -> Path:
        return self.processed_dir / "stack"

    @property
    def raw_dir(self) -> Path:
        # raw acquisition is region-specific (clipped to the AOI), so each
        # region gets its own raw tree: data/raw/<RegionName>/...
        return self.project_root / "data" / "raw" / self.name

    def ensure_dirs(self) -> None:
        for p in (self.outputs_dir, self.processed_dir, self.stack_dir):
            p.mkdir(parents=True, exist_ok=True)

    # -------------------------------------------------------------- metadata
    def metadata_path(self) -> Path:
        return self.outputs_dir / "source_metadata.json"

    def load_source_metadata(self) -> dict:
        path = self.metadata_path()
        if path.exists():
            with open(path, "r", encoding="utf-8") as fh:
                return json.load(fh)
        return {"region": self.name, "datasets": {}}

    def record_source(self, key: str, entry: dict) -> None:
        """Record one dataset entry in outputs/<Region>/source_metadata.json."""
        self.outputs_dir.mkdir(parents=True, exist_ok=True)
        meta = self.load_source_metadata()
        entry = dict(entry)
        entry.setdefault("recorded", datetime.now(timezone.utc).isoformat())
        meta.setdefault("datasets", {})[key] = entry
        with open(self.metadata_path(), "w", encoding="utf-8") as fh:
            json.dump(meta, fh, indent=2)

    # --------------------------------------------------------------- summary
    def describe(self) -> str:
        spec = self.grid_spec()
        mpix = spec["width"] * spec["height"] / 1e6
        return (
            f"Region '{self.name}': CRS={spec['crs']}, res={spec['resolution']} m, "
            f"grid={spec['width']}x{spec['height']} px ({mpix:.1f} Mpx), "
            f"outputs={self.outputs_dir}"
        )
