"""Common grid derivation, raster alignment, and the shared validity mask
(plan.md 4.1 / 4.5).

Every feature raster is reprojected -> clipped -> resampled -> aligned to the
region's common prediction grid. Continuous layers use bilinear resampling;
categorical layers use nearest-neighbour. Resampling coarse rainfall to 30 m
does NOT create 30 m accuracy (documented in source_metadata.json).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import rasterio
from rasterio.crs import CRS
from rasterio.mask import mask as rio_mask
from rasterio.warp import Resampling, reproject
from rasterio.features import geometry_mask

CONTINUOUS = {"elev", "slope", "aspect", "curvature", "ndvi",
              "rain_1d", "rain_3d", "rain_7d", "dem", "red", "nir"}
CATEGORICAL = {"lulc", "landcover", "geology"}


def resampling_for(feature: str) -> Resampling:
    """Bilinear for continuous, nearest for categorical (plan.md 4.1)."""
    key = feature.lower()
    if key in CATEGORICAL:
        return Resampling.nearest
    return Resampling.bilinear


def grid_profile(spec: dict, dtype: str = "float32", nodata=-9999.0, count: int = 1) -> dict:
    return {
        "driver": "GTiff",
        "dtype": dtype,
        "width": spec["width"],
        "height": spec["height"],
        "count": count,
        "crs": CRS.from_user_input(spec["crs"]),
        "transform": spec["transform"],
        "nodata": nodata,
        "compress": "deflate",
    }


def align_to_grid(src_path: str | Path, spec: dict, dst_path: str | Path,
                  feature: str, boundary_gdf=None, clip: bool = True) -> Path:
    """Reproject+resample src onto the common grid, then mask outside boundary."""
    resampling = resampling_for(feature)
    profile = grid_profile(spec)
    dst = np.full((spec["height"], spec["width"]), profile["nodata"], dtype=np.float32)

    with rasterio.open(src_path) as src:
        src_nodata = src.nodata
        reproject(
            source=rasterio.band(src, 1),
            destination=dst,
            src_transform=src.transform,
            src_crs=src.crs,
            src_nodata=src_nodata,
            dst_transform=spec["transform"],
            dst_crs=profile["crs"],
            dst_nodata=profile["nodata"],
            resampling=resampling,
        )

    if clip and boundary_gdf is not None:
        geoms = list(boundary_gdf.geometry)
        inside = geometry_mask(geoms, out_shape=dst.shape, transform=spec["transform"],
                               invert=True, all_touched=True)
        dst[~inside] = profile["nodata"]

    dst_path = Path(dst_path)
    dst_path.parent.mkdir(parents=True, exist_ok=True)
    with rasterio.open(dst_path, "w", **profile) as ds:
        ds.write(dst.astype(np.float32), 1)
    return dst_path


def boundary_mask(spec: dict, boundary_gdf) -> np.ndarray:
    """Boolean mask: True inside the region boundary (on the common grid)."""
    geoms = list(boundary_gdf.geometry)
    return geometry_mask(geoms, out_shape=(spec["height"], spec["width"]),
                         transform=spec["transform"], invert=True, all_touched=True)


def shared_validity_mask(stack_dir: str | Path, feature_names: list[str],
                         spec: dict, boundary_gdf) -> np.ndarray:
    """Pixel valid only if valid in ALL layers AND inside the boundary (4.5)."""
    valid = boundary_mask(spec, boundary_gdf)
    for name in feature_names:
        with rasterio.open(Path(stack_dir) / f"{name}.tif") as src:
            arr = src.read(1)
            nodata = src.nodata
        if nodata is not None:
            valid &= arr != nodata
        valid &= np.isfinite(arr)
    return valid
