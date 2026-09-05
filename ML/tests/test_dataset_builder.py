"""Phase 3: dataset construction + spatial split invariants (5.1-5.3)."""

from __future__ import annotations

import geopandas as gpd
import numpy as np
import pandas as pd
from shapely.geometry import Point

from preprocessing.dataset_builder import (
    block_grid, positives_mask, sample_negatives, assign_spatial_split,
    build_dataset,
)
from tests.conftest import write_tif


def _inventory(spec, coords):
    pts = [Point(*spec["transform"] * (c + 0.5, r + 0.5)) for r, c in coords]
    return gpd.GeoDataFrame(geometry=pts, crs=spec["crs"])


def test_block_grid_covers_pixels(tiny_spec):
    blocks = block_grid(tiny_spec, block_size_km=0.09)  # ~3px blocks
    assert blocks.shape == (tiny_spec["height"], tiny_spec["width"])
    assert blocks.max() > 0


def test_positives_from_inventory(tiny_spec, tiny_boundary_gdf):
    inv = _inventory(tiny_spec, [(10, 10)])
    pos = positives_mask(tiny_spec, tiny_boundary_gdf, inv, pos_buffer_px=1)
    assert pos[10, 10]
    assert pos.sum() >= 1


def test_negatives_avoid_positive_buffer(tiny_spec):
    valid = np.ones((20, 20), dtype=bool)
    pos = np.zeros((20, 20), dtype=bool)
    pos[10, 10] = True
    rng = np.random.default_rng(0)
    neg = sample_negatives(valid, pos, 20, neg_buffer_px=2, rng=rng)
    # no negative within the dilated positive buffer
    from scipy import ndimage
    dil = ndimage.binary_dilation(pos, iterations=2)
    assert not (neg & dil).any()


def test_spatial_split_no_leakage(tiny_spec, tiny_boundary_gdf, tmp_path):
    """All pixels in a block share the same split (no random pixel split)."""
    # two features
    write_tif(tmp_path / "elev.tif", np.random.rand(20, 20).astype(np.float32), tiny_spec)
    write_tif(tmp_path / "slope.tif", np.random.rand(20, 20).astype(np.float32), tiny_spec)
    valid = np.ones((20, 20), dtype=bool)
    pos = np.zeros((20, 20), dtype=bool); pos[5, 5] = True; pos[15, 15] = True
    neg = np.zeros((20, 20), dtype=bool); neg[0, 0] = True; neg[19, 19] = True
    blocks = block_grid(tiny_spec, block_size_km=0.15)  # ~5px blocks
    df = build_dataset(tmp_path, tiny_spec, valid, pos, neg, blocks,
                       {"train": 0.5, "val": 0.25, "test": 0.25}, seed=1)
    # invariant: one split per block_id
    per_block = df.groupby("block_id")["split"].nunique()
    assert (per_block == 1).all()
    assert set(df["split"]) <= {"train", "val", "test"}
    assert set(df["label"]) <= {0, 1}


def test_assign_spatial_split_fractions():
    block_ids = np.arange(100)
    s = assign_spatial_split(block_ids, {"train": 0.6, "val": 0.2, "test": 0.2}, seed=2)
    counts = s.value_counts()
    assert counts["train"] == 60 and counts["val"] == 20 and counts["test"] == 20
