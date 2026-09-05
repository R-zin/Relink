"""Shared training harness: Logistic Regression, Random Forest, XGBoost
(plan.md 6.1). Same splits, same metrics, saved with joblib."""

from __future__ import annotations

from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from xgboost import XGBClassifier

CONTINUOUS = ["elev", "slope", "aspect_sin", "aspect_cos", "curvature",
              "ndvi", "rain_1d", "rain_3d", "rain_7d"]
CATEGORICAL = ["lulc"]


def available_features(df: pd.DataFrame) -> tuple[list[str], list[str]]:
    cont = [c for c in CONTINUOUS if c in df.columns]
    cat = [c for c in CATEGORICAL if c in df.columns]
    return cont, cat


def design_matrix(df: pd.DataFrame, cont: list[str], cat: list[str]) -> pd.DataFrame:
    X = df[cont + cat].copy()
    for c in cat:
        X[c] = X[c].astype("category")
    return X


def build_models(global_cfg: dict, seed: int) -> dict:
    mcfg = global_cfg.get("models", {})
    lr = mcfg.get("logistic_regression", {})
    rf = mcfg.get("random_forest", {})
    xgb = mcfg.get("xgboost", {})
    return {
        "logistic_regression": Pipeline([
            ("impute", SimpleImputer(strategy="median")),
            ("scale", StandardScaler()),
            ("clf", LogisticRegression(max_iter=lr.get("max_iter", 500),
                                       random_state=seed)),
        ]),
        "random_forest": Pipeline([
            ("impute", SimpleImputer(strategy="median")),
            ("clf", RandomForestClassifier(
                n_estimators=rf.get("n_estimators", 200),
                max_depth=rf.get("max_depth", 16),
                n_jobs=rf.get("n_jobs", -1),
                random_state=seed)),
        ]),
        "xgboost": Pipeline([
            ("impute", SimpleImputer(strategy="median")),
            ("clf", XGBClassifier(
                n_estimators=xgb.get("n_estimators", 300),
                max_depth=xgb.get("max_depth", 8),
                learning_rate=xgb.get("learning_rate", 0.05),
                subsample=xgb.get("subsample", 0.8),
                colsample_bytree=xgb.get("colsample_bytree", 0.8),
                tree_method=xgb.get("tree_method", "hist"),
                enable_categorical=True,
                random_state=seed,
                eval_metric="logloss")),
        ]),
    }


def predict_proba(model, X: pd.DataFrame) -> np.ndarray:
    return model.predict_proba(X)[:, 1]


def save_model(model, path: str | Path, feature_names: list[str], meta: dict) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump({"model": model, "features": feature_names, "meta": meta}, path)
    return path


def load_model(path: str | Path):
    bundle = joblib.load(path)
    return bundle["model"], bundle["features"], bundle.get("meta", {})
