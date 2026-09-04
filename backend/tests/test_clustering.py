def _create(client, lat, lng, description, type="water"):
    r = client.post(
        "/reports",
        json={"type": type, "lat": lat, "lng": lng, "description": description},
    )
    assert r.status_code == 201
    return r.json()["id"]


def test_clusters_collapse_near_duplicates(client):
    # Two reports ~100 m apart (same flooded junction) + one ~5 km away.
    a = _create(client, 9.9800, 76.2800, "knee-deep water near junction")
    b = _create(client, 9.9808, 76.2804, "road flooded, bikes stuck")
    far = _create(client, 9.9350, 76.2800, "different flooded road")

    r = client.get("/reports/clusters")
    assert r.status_code == 200
    body = r.json()

    assert len(body["clusters"]) == 1
    cluster = body["clusters"][0]
    assert cluster["report_count"] == 2
    assert set(cluster["report_ids"]) == {a, b}
    assert abs(cluster["centroid_lat"] - (9.9800 + 9.9808) / 2) < 1e-6
    assert abs(cluster["centroid_lng"] - (76.2800 + 76.2804) / 2) < 1e-6

    assert body["noise"] == [far]


def test_clusters_empty(client):
    body = client.get("/reports/clusters").json()
    assert body == {"clusters": [], "noise": []}


def test_clusters_too_few_reports_all_noise(client):
    _create(client, 9.98, 76.28, "only one")
    body = client.get("/reports/clusters", params={"min_samples": 2}).json()
    assert body["clusters"] == []
    assert len(body["noise"]) == 1


def test_clusters_type_filter(client):
    _create(client, 9.9800, 76.2800, "w1", type="water")
    _create(client, 9.9808, 76.2804, "w2", type="water")
    _create(client, 9.9800, 76.2800, "o1", type="obstacle")
    _create(client, 9.9808, 76.2804, "o2", type="obstacle")

    body = client.get("/reports/clusters", params={"type": "water"}).json()
    assert len(body["clusters"]) == 1
    assert body["clusters"][0]["sample_description"] in {"w1", "w2"}


def test_clusters_aggregate_confirmations(client):
    a = _create(client, 9.9800, 76.2800, "w1")
    b = _create(client, 9.9808, 76.2804, "w2")
    client.post(f"/reports/{a}/confirm")
    client.post(f"/reports/{a}/confirm")
    client.post(f"/reports/{b}/confirm")

    body = client.get("/reports/clusters").json()
    cluster = body["clusters"][0]
    assert cluster["total_confirmations"] == 3
    assert cluster["last_confirmed_at"] is not None
    # sample_description is the highest-confirmation report's
    assert cluster["sample_description"] == "w1"


def test_clusters_eps_parameter_widens_grouping(client):
    _create(client, 9.9800, 76.2800, "a")
    _create(client, 9.9900, 76.2800, "b")  # ~1.1 km apart

    tight = client.get("/reports/clusters", params={"eps_m": 500}).json()
    assert tight["clusters"] == []
    assert len(tight["noise"]) == 2

    wide = client.get("/reports/clusters", params={"eps_m": 2000}).json()
    assert len(wide["clusters"]) == 1
    assert wide["noise"] == []
