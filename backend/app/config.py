"""Application settings.

Reads from environment / backend/.env. Only DATABASE_URL is required in
Phase 1; the rest are pass-throughs so later phases don't touch config
plumbing (see plans/phase_1.md §4).
"""

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Path to ML model outputs directory
    ML_OUTPUTS_DIR: str | None = None

    # Required: e.g. postgresql+asyncpg://postgres:postgres@localhost:5432/relink
    DATABASE_URL: str
    # Used by the test harness; keep separate from the dev DB.
    TEST_DATABASE_URL: str | None = None

    # Seed demo region (default: Kochi, Kerala)
    SEED_CENTER_LAT: float = 9.98
    SEED_CENTER_LNG: float = 76.28

    # --- Later phases (optional now) ---
    SUPABASE_URL: str | None = None
    SUPABASE_KEY: str | None = None
    FCM_SERVER_KEY: str | None = None
    LLM_API_KEY: str | None = None
    LLM_API_URL: str = "https://api.anthropic.com/v1/messages"
    LLM_MODEL: str = "claude-haiku-4-5-20251001"
    MEDICAL_CARD_DEMO_KEY: str | None = None
    DECRYPT_DEMO_PASS: str = "relink-demo"  # Phase 3 break-glass responder auth
    OPEN_METEO_BASE_URL: str = "https://api.open-meteo.com"
    OPEN_METEO_FLOOD_URL: str = "https://flood-api.open-meteo.com"
    OPEN_METEO_MARINE_URL: str = "https://marine-api.open-meteo.com"
    NASA_EONET_URL: str = "https://eonet.gsfc.nasa.gov/api/v3"
    SACHET_RSS_URL: str = "https://sachet.ndma.gov.in/cap_public_website/rss/rss_india.xml"
    # Copernicus Global Flood Monitoring (GFM) live WMS — EODC GeoServer.
    # Serves the current observed flood-extent composite as PNG tiles overlaid
    # on the OSM basemap (no GeoJSON/COG download). No auth required.
    GFM_WMS_URL: str = "https://geoserver.gfm.eodc.eu/geoserver/gfm/wms"
    GFM_WMS_LAYER: str = "observed_flood_extent"

    # Phase 4 demo region (Kochi / Periyar basin)
    REGION_NAME: str = "Kochi, Kerala"
    GLOFAS_LAT: float = 10.02  # Periyar river basin
    GLOFAS_LNG: float = 76.32
    STATS_TTL_MINUTES: int = 15
    AI_REVIEW_TTL_MINUTES: int = 20
    ALERTS_STATE: str = "all"

    def masked_db_host(self) -> str:
        """Host:port of the DB for startup logging, credentials masked."""
        try:
            after_scheme = self.DATABASE_URL.split("://", 1)[1]
            hostpart = after_scheme.split("@", 1)[-1]  # strip user:pass@
            return hostpart.split("/", 1)[0]
        except IndexError:
            return "(unparseable DATABASE_URL)"

    def ml_outputs_path(self) -> Path:
        """Resolve path to ML outputs directory."""
        if self.ML_OUTPUTS_DIR:
            return Path(self.ML_OUTPUTS_DIR)
        # Default: repo_root / ML / outputs
        root_outputs = Path(__file__).resolve().parents[2] / "ML" / "outputs"
        if root_outputs.exists():
            return root_outputs
        # Fallback to current working directory
        return Path("ML/outputs").resolve()


def get_settings() -> Settings:
    return Settings()
