"""Phase 4 tests: alerts ingestion, stats endpoints, AI review fallback.

External network calls are NOT made here — the alerts parse logic is tested
against a canned CAP XML fixture, and the endpoint tests rely on the
deterministic fallback paths (dams/GFM fixtures, rule-based AI review).
"""

from fastapi.testclient import TestClient


def test_alerts_test_alert_creates_red(client: TestClient):
    resp = client.post("/alerts/test-alert")
    assert resp.status_code == 201
    body = resp.json()
    assert body["severity"] == "Red"
    assert body["is_test"] == 1
    assert body["state"] == "kerala"
    assert "Aluva" in (body["headline"] or "")

    listed = client.get("/alerts?state=kerala")
    assert listed.status_code == 200
    ids = [a["id"] for a in listed.json()]
    assert body["id"] in ids


def test_stats_serves_metrics(client: TestClient):
    resp = client.get("/stats")
    assert resp.status_code == 200
    body = resp.json()
    assert body["region"] == "Kochi, Kerala"
    metrics = body["metrics"]
    # Dams + GFM come from local fixtures — always present.
    assert metrics["dams"]["count"] == 5
    assert any(d["name"] == "Mullaperiyar" for d in metrics["dams"]["dams"])
    assert metrics["gfm"]["polygon_count"] == 4
    assert metrics["gfm"]["observed_at"] == "2026-09-04T18:00:00Z"
    # Live metrics present (network available in this env) or marked stale.
    assert "discharge_m3s" in metrics["glofas"]
    assert "rainfall_24h_mm" in metrics["weather"]


def test_ai_review_returns_tag_and_summary(client: TestClient):
    resp = client.get("/stats/ai-review?region=Kochi, Kerala")
    assert resp.status_code == 200
    body = resp.json()
    assert body["risk_tag"] in ("Low", "Moderate", "High", "Severe")
    assert body["summary_text"]
    assert body["source"] in ("llm", "rule")
    assert body["region"] == "Kochi, Kerala"
    # Regression guard: when the rule fallback runs it must see the REAL
    # metrics (dams fixture always present), not empty/zero placeholders.
    if body["source"] == "rule":
        assert "reservoir data unavailable" not in body["summary_text"]
        assert "0 m³/s" not in body["summary_text"]


def test_ai_review_caches_result(client: TestClient):
    first = client.get("/stats/ai-review?region=Kochi, Kerala").json()
    second = client.get("/stats/ai-review?region=Kochi, Kerala").json()
    assert first["generated_at"] == second["generated_at"]  # served from cache


def test_cap_parse_fixture():
    from app.services.alerts_service import parse_cap_xml

    xml = """<?xml version="1.0"?>
<cap:alert xmlns:cap="urn:oasis:names:tc:emergency:cap:1.2">
<cap:identifier>IN-TEST-1</cap:identifier>
<cap:sender>Kerala-SDMA</cap:sender>
<cap:sent>2026-08-26T22:34:45+05:30</cap:sent>
<cap:info>
<cap:language>en-IN</cap:language>
<cap:category>Met</cap:category>
<cap:event>Heavy Rain</cap:event>
<cap:urgency>Expected</cap:urgency>
<cap:severity>Severe</cap:severity>
<cap:certainty>Likely</cap:certainty>
<cap:effective>2026-08-26T22:00:00+05:30</cap:effective>
<cap:onset>2026-08-26T22:34:45+05:30</cap:onset>
<cap:expires>2026-08-27T01:00:00+05:30</cap:expires>
<cap:headline>Heavy rain likely in Ernakulam.</cap:headline>
<cap:instruction>Follow SDMA guidelines.</cap:instruction>
<cap:area><cap:areaDesc>Ernakulam</cap:areaDesc></cap:area>
</cap:info>
</cap:alert>"""
    row = parse_cap_xml(xml, state="kerala")
    assert row is not None
    assert row["cap_identifier"] == "IN-TEST-1"
    assert row["severity"] == "Severe"
    assert row["event"] == "Heavy Rain"
    assert row["area_desc"] == "Ernakulam"
    assert row["issued_at"].year == 2026
    assert row["expires"] is not None


def test_rss_items_parse():
    from app.services.alerts_service import parse_rss_items

    rss = """<?xml version="1.0"?>
<rss version="2.0"><channel><title>Kerala</title>
<item><title>Alert A</title><link>https://x/cap1</link><guid>111</guid><pubDate>Wed, 26 Aug 2026 17:04:47 GMT</pubDate></item>
<item><title>Alert B</title><link>https://x/cap2</link><guid>222</guid></item>
</channel></rss>"""
    items = parse_rss_items(rss)
    assert len(items) == 2
    assert items[0]["guid"] == "111"
    assert items[0]["pubDate"].year == 2026
    assert items[1]["pubDate"] is None


def test_risk_tag_parser():
    from app.services.ai_review import parse_risk_tag

    assert parse_risk_tag("Assessment complete. RISK TAG: Severe") == "Severe"
    assert parse_risk_tag("risk tag: moderate") == "Moderate"
    assert parse_risk_tag("no tag here") is None
