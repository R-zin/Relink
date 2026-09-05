"""Generate a simplified Kerala state boundary for the prototype.

The real deployment should replace data/regions/kerala/boundary.geojson with an
official Survey of India / GADM / OSM-derived administrative boundary. This
simplified polygon (coarse outline, ~coastal shape, source recorded in
properties) lets the full pipeline run and be tested end-to-end offline.
"""

from __future__ import annotations

import json
from pathlib import Path

# Coarse simplified outline of Kerala (lon, lat), north -> south along the
# Western Ghats edge, back north along the Malabar coast. NOT survey-grade.
KERALA_OUTLINE = [
    (74.86, 12.80), (75.40, 12.55), (75.95, 11.85), (76.30, 11.35),
    (76.55, 10.95), (76.85, 10.50), (77.15, 10.05), (77.30, 9.60),
    (77.20, 9.20), (77.10, 8.80), (77.30, 8.45), (77.45, 8.20),
    (77.05, 8.08), (76.60, 8.55), (76.35, 9.00), (76.25, 9.45),
    (76.15, 10.00), (76.10, 10.45), (75.85, 10.90), (75.65, 11.30),
    (75.55, 11.75), (75.30, 12.10), (74.90, 12.65),
]

# Coarse simplified outline of Idukki district (region-switch proof).
IDUKKI_OUTLINE = [
    (76.55, 10.15), (77.05, 10.25), (77.30, 10.00), (77.35, 9.65),
    (77.25, 9.35), (77.05, 9.15), (76.75, 9.20), (76.60, 9.50),
    (76.50, 9.80),
]


def write_boundary(out_path: Path, outline: list[tuple[float, float]], name: str,
                   source: str, note: str) -> Path:
    coords = outline + [outline[0]]
    gj = {
        "type": "FeatureCollection",
        "name": name,
        "crs": {"type": "name", "properties": {"name": "urn:ogc:def:crs:OGC:1.3:CRS84"}},
        "features": [
            {
                "type": "Feature",
                "properties": {
                    "name": name,
                    "source": source,
                    "note": note,
                },
                "geometry": {"type": "Polygon", "coordinates": [coords]},
            }
        ],
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(gj, fh, indent=2)
    return out_path


def main() -> None:
    root = Path(__file__).resolve().parent
    p1 = write_boundary(
        root / "data" / "regions" / "kerala" / "boundary.geojson",
        KERALA_OUTLINE,
        "Kerala",
        source="simplified prototype outline (replace with Survey of India / GADM / OSM official boundary)",
        note="Simplified coarse boundary for pipeline development; not survey-grade.",
    )
    p2 = write_boundary(
        root / "data" / "regions" / "idukki" / "boundary.geojson",
        IDUKKI_OUTLINE,
        "Idukki",
        source="simplified prototype outline (replace with official district boundary)",
        note="Simplified coarse boundary for region-switch proof.",
    )
    print(f"wrote {p1}")
    print(f"wrote {p2}")


if __name__ == "__main__":
    main()
