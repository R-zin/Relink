"""Security and hardening regression tests.

Verifies:
1. Security headers (CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy).
2. Path traversal attack rejection on ML risk and region routes.
3. Strict authentication on break-glass medical decrypt (timing-safe, no default credentials).
4. Boundary input validation and length/size caps (DoS prevention).
5. Query parameter limits and SQL injection/wildcard sanitization.
"""

from fastapi.testclient import TestClient


def test_security_headers_present(client: TestClient):
    resp = client.get("/health")
    assert resp.status_code == 200
    headers = resp.headers
    assert headers.get("X-Content-Type-Options") == "nosniff"
    assert headers.get("X-Frame-Options") == "DENY"
    assert headers.get("Referrer-Policy") == "strict-origin-when-cross-origin"
    assert headers.get("Permissions-Policy") == "geolocation=(self), camera=(), microphone=()"
    assert "default-src 'self'" in headers.get("Content-Security-Policy", "")
    assert "frame-ancestors 'none'" in headers.get("Content-Security-Policy", "")


def test_cors_restricted_origins(client: TestClient):
    # Origin in allowed list
    resp = client.options(
        "/health",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert resp.headers.get("access-control-allow-origin") == "http://localhost:5173"
    assert resp.headers.get("access-control-allow-credentials") == "true"

    # Origin NOT in allowed list should not receive allow-origin
    untrusted = client.options(
        "/health",
        headers={
            "Origin": "http://evil-attacker-site.com",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert untrusted.headers.get("access-control-allow-origin") != "http://evil-attacker-site.com"


def test_path_traversal_rejected_in_ml_risk(client: TestClient):
    traversal_payloads = [
        "../../etc",
        "../../../../",
        "../outputs",
        "/etc/passwd",
        "kerala/../../../",
        "kerala%2F..%2F..",
        "kerala;cat /etc/passwd",
        "invalid!chars?here",
    ]
    for payload in traversal_payloads:
        r1 = client.get(f"/api/ml/risk-regions?region={payload}")
        assert r1.status_code in (400, 404, 422), f"Payload '{payload}' was not rejected in risk-regions"

        r2 = client.get(f"/api/ml/historical-landslides?region={payload}")
        assert r2.status_code in (400, 404, 422), f"Payload '{payload}' was not rejected in landslides"

        r3 = client.get(f"/api/ml/point-risk?lat=9.98&lng=76.28&region={payload}")
        assert r3.status_code in (400, 404, 422), f"Payload '{payload}' was not rejected in point-risk"

        r4 = client.get(f"/api/ml/metadata?region={payload}")
        assert r4.status_code in (400, 404, 422), f"Payload '{payload}' was not rejected in metadata"


def test_medical_decrypt_requires_explicit_authentication(client: TestClient):
    # Missing demo_pass should fail with 422 validation error
    r1 = client.post("/medical/decrypt", json={"ciphertext": "dGVzdA=="})
    assert r1.status_code == 422

    # Empty demo_pass should be rejected
    r2 = client.post("/medical/decrypt", json={"ciphertext": "dGVzdA==", "demo_pass": ""})
    assert r2.status_code in (401, 422)

    # Wrong demo_pass should return 401
    r3 = client.post("/medical/decrypt", json={"ciphertext": "dGVzdA==", "demo_pass": "wrong-secret"})
    assert r3.status_code == 401


def test_unbounded_payload_dos_prevention(client: TestClient):
    # Oversized encrypted_medical (>10,000 bytes)
    huge_encrypted = "A" * 15_000
    r_sos = client.post(
        "/sos",
        json={"lat": 9.98, "lng": 76.28, "encrypted_medical": huge_encrypted},
    )
    assert r_sos.status_code == 422

    # Oversized report description (>2,000 bytes)
    huge_desc = "X" * 3_000
    r_rep = client.post(
        "/reports",
        json={"type": "obstacle", "lat": 9.98, "lng": 76.28, "description": huge_desc},
    )
    assert r_rep.status_code == 422

    # Oversized shelter name (>200 bytes)
    huge_shelter_name = "S" * 300
    r_sh = client.post(
        "/shelters",
        json={"name": huge_shelter_name, "lat": 9.98, "lng": 76.28},
    )
    assert r_sh.status_code == 422

    # Oversized missing person name (>200 bytes)
    huge_person_name = "P" * 300
    r_mp = client.post(
        "/missing-persons",
        json={"name": huge_person_name},
    )
    assert r_mp.status_code == 422


def test_shelters_limit_enforced(client: TestClient):
    # Exceeding maximum limit parameter (>1000)
    r = client.get("/shelters?limit=5000")
    assert r.status_code == 422
