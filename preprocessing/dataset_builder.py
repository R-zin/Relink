"""Pixel-wise dataset construction with spatial block splits (plan.md Phase 3).

Positives: pixels intersecting inventory points (buffered) inside the region.
Negatives: sampled valid pixels outside all inventory events with a buffer
distance around positives. A negative means "not in the inventory", not
"landslide impossible". Splits are block-based (no random pixel splits).
"""

from __future__ import annotations

from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from rasterio.features import geometry_mask
from scipy import ndimage

FEATURE_COLUMNS = [
    "elev", "slope", "aspect_sin", "aspect_cos", "curvature",
    "ndvi", "lulc", "rain_1d", "rain_3d", "rain_7d",
]


def block_grid(spec: dict, block_size_km: float) -> np.ndarray:
    """Assign each pixel a block_id from a regular block grid over the AOI."""
    res = spec["resolution"]
    block_px = max(1, int(round(block_size_km * 1000 / res)))
    h, w = spec["height"], spec["width"]
    rows = np.arange(h) // block_px
    cols = np.arange(w) // block_px
    ncols = (w // block_px) + 1
    block_id = (rows[:, None] * ncols + cols[None, :]).astype(np.int32)
    return np.broadcast_to(block_id, (h, w)).copy()


def positives_mask(spec: dict, boundary_gdf, inventory_gdf, pos_buffer_px: int = 1) -> np.ndarray:
    """Rasterise inventory points buffered to >= 1 pixel, clipped to boundary."""
    inv = inventory_gdf.to_crs(spec["crs"])
    res = spec["resolution"]
    buffered = inv.geometry.buffer(res * max(1, pos_buffer_px))
    pos = geometry_mask(list(buffered), out_shape=(spec["height"], spec["width"]),
                        transform=spec["transform"], invert=True, all_touched=True)
    return pos


def sample_negatives(valid: np.ndarray, pos: np.ndarray, n_neg: int,
                     neg_buffer_px: int, rng: np.random.Generator) -> np.ndarray:
    """Sample negative pixels outside positives with a buffer (boundary ambiguity)."""
    if neg_buffer_px > 0:
        dil = ndimage.binary_dilation(pos, iterations=int(neg_buffer_px))
    else:
        dil = pos
    eligible = valid & ~dil
    idx = np.flatnonzero(eligible.ravel())
    if idx.size == 0:
        return np.zeros_like(pos)
    take = min(n_neg, idx.size)
    sel = rng.choice(idx, size=take, replace=False)
    neg = np.zeros_like(pos)
    neg.ravel()[sel] = True
    return neg


def assign_spatial_split(block_ids: np.ndarray, fractions: dict, seed: int) -> pd.Series:
    """Assign blocks (not pixels) to train/val/test -> no spatial leakage."""
    uniq = np.unique(block_ids)
    rng = np.random.default_rng(seed)
    rng.shuffle(uniq)
    n = len(uniq)
    n_train = int(round(n * fractions.get("train", 0.6)))
    n_val = int(round(n * fractions.get("val", 0.2)))
    split = {}
    for i, b in enumerate(uniq):
        if i < n_train:
            split[b] = "train"
        elif i < n_train + n_val:
            split[b] = "val"
        else:
            split[b] = "test"
    return pd.Series(block_ids).map(split)


def build_dataset(stack_dir: str | Path, spec: dict, valid: np.ndarray,
                  pos: np.ndarray, neg: np.ndarray, block_ids: np.ndarray,
                  fractions: dict, seed: int) -> pd.DataFrame:
    """Assemble one row per sampled pixel."""
    stack_dir = Path(stack_dir)
    keep = pos | neg
    labels = np.where(pos, 1, 0).astype(np.int8)
    rows_idx, cols_idx = np.nonzero(keep)

    data = {
        "pixel_id": (rows_idx * spec["width"] + cols_idx).astype(np.int64),
        "row": rows_idx,
        "col": cols_idx,
        "block_id": block_ids[rows_idx, cols_idx],
        "label": labels[rows_idx, cols_idx],
    }
    # x/y pixel-centre coordinates in grid CRS
    tr = spec["transform"]
    xs, ys = tr * (cols_idx + 0.5, rows_idx + 0.5)
    data["x"] = xs
    data["y"] = ys

    for name in FEATURE_COLUMNS:
        f = stack_dir / f"{name}.tif"
        if not f.exists():
            continue
        with rasterio.open(f) as src:
            arr = src.read(1)
            nodata = src.nodata
        vals = arr[rows_idx, cols_idx].astype(np.float32)
        if nodata is not None:
            vals = np.where(vals == nodata, np.nan, vals)
        data[name] = vals

    df = pd.DataFrame(data)
    df["split"] = assign_spatial_split(df["block_id"].to_numpy(), fractions, seed).to_numpy()
    # categorical features stay integer-coded for native-categorical handling
    if "lulc" in df.columns:
        df["lulc"] = df["lulc"].fillna(-1).astype(np.int16)
    return df
