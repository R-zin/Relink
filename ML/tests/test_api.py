"""Phase 7: API smoke tests (9.1 / plan.md Phase 9 tests)."""

from __future__ import annotations

import json

import pytest
from fastapi.testclient import TestClient

from api.main import app

client = TestClient(app)


def test_metadata_endpoint_idukki():
    r = client.get("/api/metadata", params={"region": "idukki"})
    assert r.status_code == 200
    d = r.json()
    assert d["region"] == "Idukki"
    assert "disclaimer" in d
    assert "not a detection of an active event" in d["disclaimer"]
    assert "rainfall_resolution_note" in d


def test_metadata_unknown_region_404():
    r = client.get("/api/metadata", params={"region": "nope"})
    assert r.status_code == 404


def test_risk_regions_geojson():
    r = client.get("/api/risk-regions", params={"region": "idukki"})
    assert r.status_code == 200
    gj = r.json()
    assert gj["type"] == "FeatureCollection"


def test_historical_landslides_geojson():
    r = client.get("/api/historical-landslides", params={"region": "idukki"})
    assert r.status_code == 200
    assert r.json()["type"] == "FeatureCollection"


def test_point_risk_and_terminology():
    # center of Idukki simplified boundary (~76.9, 9.7)
    r = client.get("/api/point-risk", params={"lat": 9.7, "lon": 76.9, "region": "idukki"})
    assert r.status_code == 200
    d = r.json()
    assert "disclaimer" in d
    # terminology discipline: never "landslide detected"
    assert "landslide detected" not in json.dumps(d).lower()
