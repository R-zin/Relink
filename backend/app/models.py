"""SQLAlchemy models mirroring alembic migration 0001 (source of truth for DDL).

Column definitions must stay in sync with alembic/versions/0001_initial_schema.py.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, Text, func, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


def _uuid_pk() -> Mapped[uuid.UUID]:
    return mapped_column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))


class Device(Base):
    __tablename__ = "devices"

    id: Mapped[uuid.UUID] = _uuid_pk()
    public_key: Mapped[str | None] = mapped_column(Text)  # reserved for v2
    last_seen: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    platform: Mapped[str | None] = mapped_column(Text)


class SosEvent(Base):
    __tablename__ = "sos_events"

    id: Mapped[uuid.UUID] = _uuid_pk()
    device_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("devices.id"))
    lat: Mapped[float]
    lng: Mapped[float]
    plaintext_medical: Mapped[dict | None] = mapped_column(JSONB)
    encrypted_medical: Mapped[str | None] = mapped_column(Text)  # opaque base64 AES-GCM (Phase 3)
    status: Mapped[str] = mapped_column(Text, server_default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (Index("ix_sos_events_status", "status"),)


class Report(Base):
    __tablename__ = "reports"

    id: Mapped[uuid.UUID] = _uuid_pk()
    type: Mapped[str] = mapped_column(Text)  # 'obstacle' | 'disease' | 'water'
    lat: Mapped[float]
    lng: Mapped[float]
    description: Mapped[str | None] = mapped_column(Text)
    device_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("devices.id"))
    confirm_count: Mapped[int] = mapped_column(Integer, server_default="0")
    last_confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        Index("ix_reports_lat_lng", "lat", "lng"),
        Index("ix_reports_type", "type"),
    )


class MissingPerson(Base):
    __tablename__ = "missing_persons"

    id: Mapped[uuid.UUID] = _uuid_pk()
    name: Mapped[str] = mapped_column(Text)
    last_seen_lat: Mapped[float | None]
    last_seen_lng: Mapped[float | None]
    description: Mapped[str | None] = mapped_column(Text)
    reporter_device_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("devices.id"))
    status: Mapped[str] = mapped_column(Text, server_default="missing")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (Index("ix_missing_persons_lower_name", func.lower(name)),)


class Shelter(Base):
    __tablename__ = "shelters"

    id: Mapped[uuid.UUID] = _uuid_pk()
    name: Mapped[str] = mapped_column(Text)
    lat: Mapped[float]
    lng: Mapped[float]
    contact_info: Mapped[str | None] = mapped_column(Text)
    confirm_count: Mapped[int] = mapped_column(Integer, server_default="0")
    last_confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    added_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("devices.id"))

    __table_args__ = (Index("ix_shelters_lat_lng", "lat", "lng"),)


class StatsCache(Base):
    __tablename__ = "stats_cache"

    id: Mapped[uuid.UUID] = _uuid_pk()
    metric: Mapped[str] = mapped_column(Text)
    value_json: Mapped[dict | None] = mapped_column(JSONB)
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (Index("ix_stats_cache_metric_fetched_at", "metric", fetched_at.desc()),)


class AiReviewCache(Base):
    __tablename__ = "ai_review_cache"

    id: Mapped[uuid.UUID] = _uuid_pk()
    region: Mapped[str] = mapped_column(Text)
    summary_text: Mapped[str | None] = mapped_column(Text)
    risk_tag: Mapped[str | None] = mapped_column(Text)  # 'Low' | 'Moderate' | 'High' | 'Severe'
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
