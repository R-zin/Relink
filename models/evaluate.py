"""Shared evaluation metrics on spatial validation/test sets (plan.md 6.2)."""

from __future__ import annotations

import numpy as np
from sklearn.metrics import (
    accuracy_score, average_precision_score, confusion_matrix,
    f1_score, precision_score, recall_score, roc_auc_score,
)


def classification_metrics(y_true: np.ndarray, y_prob: np.ndarray,
                           threshold: float = 0.5) -> dict:
    y_pred = (y_prob >= threshold).astype(int)
    out = {
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall": float(recall_score(y_true, y_pred, zero_division=0)),
        "f1": float(f1_score(y_true, y_pred, zero_division=0)),
        "threshold": float(threshold),
    }
    if len(np.unique(y_true)) > 1:
        out["roc_auc"] = float(roc_auc_score(y_true, y_prob))
        out["pr_auc"] = float(average_precision_score(y_true, y_prob))
    else:
        out["roc_auc"] = None
        out["pr_auc"] = None
    out["confusion_matrix"] = confusion_matrix(y_true, y_pred, labels=[0, 1]).tolist()
    return out


def select_best(metrics: dict, primary: str = "pr_auc", secondary: str = "roc_auc") -> str:
    """Choose best model by spatial-validation PR-AUC then ROC-AUC (6.3)."""
    def key(name):
        m = metrics[name].get("val", {})
        return (m.get(primary) or -1, m.get(secondary) or -1)

    return max(metrics.keys(), key=key)
