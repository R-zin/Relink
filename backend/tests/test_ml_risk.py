"""Unit tests for ML flood & landslide susceptibility endpoints."""

from fastapi.testclient import TestClient


def test_ml_risk_regions_returns_geojson(client: TestClient):
    resp = client.get("/api/ml/risk-regions?region=idukki")
    assert resp.status_code == 200
    data = resp.json()
    assert data["type"] == "FeatureCollection"
    assert "features" in data
    assert len(data["features"]) > 0
    first = data["features"][0]
    assert "geometry" in first
    assert "properties" in first
    assert "risk_class" in first["properties"]
    assert "risk_name" in first["properties"]


def test_ml_risk_regions_bbox_filter(client: TestClient):
    # Small bbox around Idukki feature
    resp = client.get("/api/ml/risk-regions?region=idukki&bbox=77.25,9.9,77.3,10.05")
    assert resp.status_code == 200
    data = resp.json()
    assert data["type"] == "FeatureCollection"
    assert len(data["features"]) > 0


def test_ml_point_risk_check(client: TestClient):
    # Test point inside known Idukki high risk polygon
    resp = client.get("/api/ml/point-risk?region=idukki&lat=10.03&lng=77.264")
    assert resp.status_code == 200
    data = resp.json()
    assert "in_risk_zone" in data
    assert "disclaimer" in data
    assert "susceptibility" in data["disclaimer"].lower() or "model" in data["disclaimer"].lower()


def test_ml_metadata_serves_metrics(client: TestClient):
    resp = client.get("/api/ml/metadata?region=idukki")
    assert resp.status_code == 200
    data = resp.json()
    assert "model_metrics" in data
    assert "sources" in data
    assert "disclaimer" in data


def test_ml_risk_regions_not_found(client: TestClient):
    resp = client.get("/api/ml/risk-regions?region=non_existent_region")
    assert resp.status_code == 404
