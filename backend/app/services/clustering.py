"""DBSCAN clustering of hazard reports.

Pure service: takes ORM `Report` rows, returns cluster summaries. No SQL in
here — the router fetches rows (optionally type-filtered) and delegates.

sklearn's haversine metric expects radians and returns great-circle distance
in radians; multiplying by Earth's radius (m) gives meters. So an epsilon in
meters is eps_m / 6_371_000 radians.
"""

import math
from dataclasses import dataclass, field
from datetime import datetime
from uuid import UUID

import numpy as np
from sklearn.cluster import DBSCAN

EARTH_RADIUS_M = 6_371_000.0


@dataclass
class Cluster:
    cluster_id: str
    centroid_lat: float
    centroid_lng: float
    report_count: int
    total_confirmations: int
    last_confirmed_at: datetime | None
    sample_description: str | None
    report_ids: list[UUID]


@dataclass
class ClusterResult:
    clusters: list[Cluster] = field(default_factory=list)
    noise: list[UUID] = field(default_factory=list)


def cluster_reports(reports: list, eps_m: float = 500, min_samples: int = 2) -> ClusterResult:
    """Group reports into geographic clusters.

    `reports` are rows with .id, .lat, .lng, .confirm_count, .last_confirmed_at,
    .description (ORM `Report` instances, but duck-typed for easy unit tests).
    """
    result = ClusterResult()
    if not reports:
        return result
    # Guard: too few points to ever form a cluster -> everything is noise,
    # and sklearn would raise on min_samples > n_samples anyway.
    if len(reports) < min_samples:
        result.noise = [r.id for r in reports]
        return result

    coords = np.array([[math.radians(r.lat), math.radians(r.lng)] for r in reports])
    labels = DBSCAN(
        eps=eps_m / EARTH_RADIUS_M, min_samples=min_samples, metric="haversine"
    ).fit_predict(coords)

    by_label: dict[int, list[int]] = {}
    for idx, label in enumerate(labels):
        by_label.setdefault(int(label), []).append(idx)

    for label, idxs in sorted(by_label.items()):
        if label == -1:
            result.noise.extend(reports[i].id for i in idxs)
            continue
        members = [reports[i] for i in idxs]
        confirmed_times = [m.last_confirmed_at for m in members if m.last_confirmed_at is not None]
        # Description of the highest-confirmation report represents the cluster.
        representative = max(members, key=lambda m: m.confirm_count or 0)
        result.clusters.append(
            Cluster(
                cluster_id=f"cluster-{label}",
                centroid_lat=sum(m.lat for m in members) / len(members),
                centroid_lng=sum(m.lng for m in members) / len(members),
                report_count=len(members),
                total_confirmations=sum(m.confirm_count or 0 for m in members),
                last_confirmed_at=max(confirmed_times) if confirmed_times else None,
                sample_description=representative.description,
                report_ids=[m.id for m in members],
            )
        )
    return result
