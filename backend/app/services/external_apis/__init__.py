"""External hazard telemetry adapters (Phase 4).

Every adapter fetches from a live, no-auth public API with a short timeout and
persists the parsed payload in `stats_cache` via `cached_fetch`. Failures
degrade gracefully: serve the most recent cached row (`stale: true`), or a
local fixture (`fallback: true`) when no cache exists yet. An emergency stats
response must never 500 because an external API is down.
"""

from app.services.external_apis.cache import cached_fetch

__all__ = ["cached_fetch"]
