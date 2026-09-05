"""Phase 4: training harness, metrics, model selection (6.1-6.3)."""

from __future__ import annotations

import numpy as np
import pandas as pd

from models.train import build_models, design_matrix, available_features, predict_proba
from models.evaluate import classification_metrics, select_best


def _toy_df(n=200, seed=0):
    rng = np.random.default_rng(seed)
    slope = rng.uniform(0, 45, n)
    ndvi = rng.uniform(0, 1, n)
    logit = -4 + 0.12 * slope - 1.5 * ndvi
    p = 1 / (1 + np.exp(-logit))
    y = (rng.random(n) < p).astype(int)
    return pd.DataFrame({
        "elev": rng.uniform(0, 2000, n),
        "slope": slope,
        "aspect_sin": rng.uniform(-1, 1, n),
        "aspect_cos": rng.uniform(-1, 1, n),
        "curvature": rng.normal(0, 1, n),
        "ndvi": ndvi,
        "lulc": rng.integers(0, 4, n),
        "rain_1d": rng.uniform(0, 100, n),
        "rain_3d": rng.uniform(0, 200, n),
        "rain_7d": rng.uniform(0, 400, n),
        "label": y,
    })


def test_three_models_train_and_predict():
    df = _toy_df()
    cont, cat = available_features(df)
    X = design_matrix(df, cont, cat)
    y = df["label"].to_numpy()
    cfg = {"models": {}}
    models = build_models(cfg, seed=42)
    assert set(models) == {"logistic_regression", "random_forest", "xgboost"}
    for name, model in models.items():
        model.fit(X, y)
        prob = predict_proba(model, X)
        assert prob.shape == (len(df),)
        assert ((prob >= 0) & (prob <= 1)).all()


def test_metrics_keys():
    y = np.array([0, 0, 1, 1, 0, 1])
    p = np.array([0.1, 0.4, 0.7, 0.9, 0.2, 0.6])
    m = classification_metrics(y, p)
    for k in ("accuracy", "precision", "recall", "f1", "roc_auc", "pr_auc",
              "confusion_matrix"):
        assert k in m


def test_select_best_prefers_higher_pr_auc():
    metrics = {
        "a": {"val": {"pr_auc": 0.5, "roc_auc": 0.7}},
        "b": {"val": {"pr_auc": 0.6, "roc_auc": 0.65}},
    }
    assert select_best(metrics) == "b"
