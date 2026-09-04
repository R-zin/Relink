import uuid


def _create(client, **overrides):
    body = {"type": "water", "lat": 9.98, "lng": 76.28, "description": "knee-deep water"}
    body.update(overrides)
    return client.post("/reports", json=body)


def test_create_report(client):
    r = _create(client)
    assert r.status_code == 201
    body = r.json()
    assert body["type"] == "water"
    assert body["confirm_count"] == 0
    assert body["last_confirmed_at"] is None


def test_create_report_invalid_type_422(client):
    r = _create(client, type="fire")
    assert r.status_code == 422


def test_confirm_report_increments_and_stamps(client):
    report_id = _create(client).json()["id"]

    r = client.post(f"/reports/{report_id}/confirm")
    assert r.status_code == 200
    body = r.json()
    assert body["confirm_count"] == 1
    assert body["last_confirmed_at"] is not None

    r = client.post(f"/reports/{report_id}/confirm")
    assert r.json()["confirm_count"] == 2


def test_confirm_unknown_report_404(client):
    r = client.post(f"/reports/{uuid.uuid4()}/confirm")
    assert r.status_code == 404


def test_list_reports_radius_filter(client):
    _create(client, lat=9.98, lng=76.28, description="near")       # ~0 km away
    _create(client, lat=9.98, lng=76.40, description="mid")        # ~13 km away
    _create(client, lat=10.40, lng=76.30, description="far")       # ~47 km away

    near = client.get("/reports", params={"lat": 9.98, "lng": 76.28, "radius_km": 2}).json()
    assert {r["description"] for r in near} == {"near"}

    wide = client.get("/reports", params={"lat": 9.98, "lng": 76.28, "radius_km": 20}).json()
    assert {r["description"] for r in wide} == {"near", "mid"}


def test_list_reports_type_filter(client):
    _create(client, type="water", description="w")
    _create(client, type="obstacle", description="o")
    water = client.get("/reports", params={"type": "water"}).json()
    assert [r["description"] for r in water] == ["w"]
