def _create(client, **overrides):
    body = {"name": "Anil Kumar", "last_seen_lat": 9.98, "last_seen_lng": 76.28}
    body.update(overrides)
    return client.post("/missing-persons", json=body)


def test_create_missing_person(client):
    r = _create(client, description="last seen near the market")
    assert r.status_code == 201
    body = r.json()
    assert body["name"] == "Anil Kumar"
    assert body["status"] == "missing"


def test_search_name_case_insensitive(client):
    _create(client, name="Anil Kumar")
    _create(client, name="MEENA ANIL")
    _create(client, name="Joseph Mathew")

    r = client.get("/missing-persons/search", params={"name": "anil"})
    assert r.status_code == 200
    names = {p["name"] for p in r.json()}
    assert names == {"Anil Kumar", "MEENA ANIL"}


def test_search_radius_filter(client):
    _create(client, name="Near Person", last_seen_lat=9.98, last_seen_lng=76.28)
    _create(client, name="Far Person", last_seen_lat=11.00, last_seen_lng=77.00)

    r = client.get("/missing-persons/search", params={"lat": 9.98, "lng": 76.28, "radius_km": 30})
    assert {p["name"] for p in r.json()} == {"Near Person"}


def test_search_name_and_radius_anded(client):
    _create(client, name="Anil Near", last_seen_lat=9.98, last_seen_lng=76.28)
    _create(client, name="Anil Far", last_seen_lat=11.00, last_seen_lng=77.00)

    r = client.get(
        "/missing-persons/search",
        params={"name": "anil", "lat": 9.98, "lng": 76.28, "radius_km": 30},
    )
    assert {p["name"] for p in r.json()} == {"Anil Near"}


def test_search_empty_returns_newest(client):
    for i in range(3):
        _create(client, name=f"Person {i}")
    r = client.get("/missing-persons/search")
    assert len(r.json()) == 3


def test_create_missing_person_requires_name(client):
    r = client.post("/missing-persons", json={"description": "no name"})
    assert r.status_code == 422
