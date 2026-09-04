import uuid


def _create(client, **overrides):
    body = {"name": "Govt. HSS Relief Camp", "lat": 9.98, "lng": 76.28}
    body.update(overrides)
    return client.post("/shelters", json=body)


def test_create_shelter(client):
    r = _create(client, contact_info="ward councillor: +91-9800000000")
    assert r.status_code == 201
    body = r.json()
    assert body["name"] == "Govt. HSS Relief Camp"
    assert body["confirm_count"] == 0


def test_confirm_shelter(client):
    shelter_id = _create(client).json()["id"]
    r = client.post(f"/shelters/{shelter_id}/confirm")
    assert r.status_code == 200
    body = r.json()
    assert body["confirm_count"] == 1
    assert body["last_confirmed_at"] is not None


def test_confirm_unknown_shelter_404(client):
    r = client.post(f"/shelters/{uuid.uuid4()}/confirm")
    assert r.status_code == 404


def test_list_shelters_ordered_by_trust(client):
    low = _create(client, name="Low Trust").json()["id"]
    high = _create(client, name="High Trust").json()["id"]
    _create(client, name="No Trust")

    for _ in range(3):
        client.post(f"/shelters/{high}/confirm")
    client.post(f"/shelters/{low}/confirm")

    names = [s["name"] for s in client.get("/shelters").json()]
    assert names == ["High Trust", "Low Trust", "No Trust"]


def test_list_shelters_radius_filter(client):
    _create(client, name="Near Camp", lat=9.98, lng=76.28)
    _create(client, name="Far Camp", lat=11.50, lng=77.50)

    r = client.get("/shelters", params={"lat": 9.98, "lng": 76.28, "radius_km": 30})
    assert {s["name"] for s in r.json()} == {"Near Camp"}
