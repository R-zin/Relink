"""Application settings.

Reads from environment / backend/.env. Only DATABASE_URL is required in
Phase 1; the rest are pass-throughs so later phases don't touch config
plumbing (see plans/phase_1.md §4).
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

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
    MEDICAL_CARD_DEMO_KEY: str | None = None
    DECRYPT_DEMO_PASS: str = "relink-demo"  # Phase 3 break-glass responder auth
    OPEN_METEO_BASE_URL: str = "https://api.open-meteo.com"
    NASA_EONET_URL: str = "https://eonet.gsfc.nasa.gov/api/v3"
    SACHET_RSS_URL: str | None = None

    def masked_db_host(self) -> str:
        """Host:port of the DB for startup logging, credentials masked."""
        try:
            after_scheme = self.DATABASE_URL.split("://", 1)[1]
            hostpart = after_scheme.split("@", 1)[-1]  # strip user:pass@
            return hostpart.split("/", 1)[0]
        except IndexError:
            return "(unparseable DATABASE_URL)"


def get_settings() -> Settings:
    return Settings()
