import uuid


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_create_sos_minimal(client):
    r = client.post("/sos", json={"lat": 9.98, "lng": 76.28})
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "active"
    assert uuid.UUID(body["id"])  # parses
    assert "created_at" in body


def test_create_sos_with_medical_and_device(client):
    device_id = str(uuid.uuid4())
    payload = {
        "device_id": device_id,
        "lat": 9.98,
        "lng": 76.28,
        "plaintext_medical": {
            "name": "Asha Pillai",
            "blood_group": "O+",
            "allergies": ["penicillin"],
            "emergency_contact": {"name": "Raj", "phone": "+91-9800000000"},
        },
        "encrypted_medical": "dGVzdA==",  # opaque; stored verbatim
    }
    r = client.post("/sos", json=payload)
    assert r.status_code == 201

    listed = client.get("/sos").json()
    assert len(listed) == 1
    assert listed[0]["device_id"] == device_id
    assert listed[0]["plaintext_medical"]["blood_group"] == "O+"
    assert listed[0]["encrypted_medical"] == "dGVzdA=="


def test_create_sos_non_uuid_device_id_stores_null(client):
    r = client.post("/sos", json={"device_id": "mesh-node-7", "lat": 9.98, "lng": 76.28})
    assert r.status_code == 201
    listed = client.get("/sos").json()
    assert listed[0]["device_id"] is None


def test_create_sos_invalid_body_422(client):
    r = client.post("/sos", json={"lat": 9.98})  # missing lng
    assert r.status_code == 422
    r = client.post("/sos", json={"lat": 200, "lng": 76.28})  # out of range
    assert r.status_code == 422


def test_list_sos_status_filter_and_order(client):
    client.post("/sos", json={"lat": 9.98, "lng": 76.28})
    client.post("/sos", json={"lat": 9.99, "lng": 76.29})

    all_events = client.get("/sos").json()
    assert len(all_events) == 2
    active = client.get("/sos", params={"status": "active"}).json()
    assert len(active) == 2
    resolved = client.get("/sos", params={"status": "resolved"}).json()
    assert resolved == []
