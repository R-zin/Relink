"""initial schema

Hand-written per plans/phase_1.md §3 (no autogenerate). Creates pgcrypto,
all seven tables, and the specified indexes. Plain Postgres — must work on
both local Postgres 15+ and Supabase.

Revision ID: 0001
Revises:
Create Date: 2026-09-05
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto;")

    op.create_table(
        "devices",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("public_key", sa.Text(), nullable=True),
        sa.Column("last_seen", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("platform", sa.Text(), nullable=True),
    )

    op.create_table(
        "sos_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("device_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("devices.id"), nullable=True),
        sa.Column("lat", sa.Double(), nullable=False),
        sa.Column("lng", sa.Double(), nullable=False),
        sa.Column("plaintext_medical", postgresql.JSONB(), nullable=True),
        sa.Column("encrypted_medical", sa.Text(), nullable=True),
        sa.Column("status", sa.Text(), nullable=False, server_default="active"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_sos_events_status", "sos_events", ["status"])

    op.create_table(
        "reports",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("type", sa.Text(), nullable=False),
        sa.Column("lat", sa.Double(), nullable=False),
        sa.Column("lng", sa.Double(), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("device_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("devices.id"), nullable=True),
        sa.Column("confirm_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_reports_lat_lng", "reports", ["lat", "lng"])
    op.create_index("ix_reports_type", "reports", ["type"])

    op.create_table(
        "missing_persons",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("last_seen_lat", sa.Double(), nullable=True),
        sa.Column("last_seen_lng", sa.Double(), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("reporter_device_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("devices.id"), nullable=True),
        sa.Column("status", sa.Text(), nullable=False, server_default="missing"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_missing_persons_lower_name", "missing_persons", [sa.text("lower(name)")])

    op.create_table(
        "shelters",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("lat", sa.Double(), nullable=False),
        sa.Column("lng", sa.Double(), nullable=False),
        sa.Column("contact_info", sa.Text(), nullable=True),
        sa.Column("confirm_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("added_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("devices.id"), nullable=True),
    )
    op.create_index("ix_shelters_lat_lng", "shelters", ["lat", "lng"])

    op.create_table(
        "stats_cache",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("metric", sa.Text(), nullable=False),
        sa.Column("value_json", postgresql.JSONB(), nullable=True),
        sa.Column("fetched_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_stats_cache_metric_fetched_at", "stats_cache", ["metric", sa.text("fetched_at DESC")])

    op.create_table(
        "ai_review_cache",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("region", sa.Text(), nullable=False),
        sa.Column("summary_text", sa.Text(), nullable=True),
        sa.Column("risk_tag", sa.Text(), nullable=True),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("ai_review_cache")
    op.drop_index("ix_stats_cache_metric_fetched_at", table_name="stats_cache")
    op.drop_table("stats_cache")
    op.drop_index("ix_shelters_lat_lng", table_name="shelters")
    op.drop_table("shelters")
    op.drop_index("ix_missing_persons_lower_name", table_name="missing_persons")
    op.drop_table("missing_persons")
    op.drop_index("ix_reports_type", table_name="reports")
    op.drop_index("ix_reports_lat_lng", table_name="reports")
    op.drop_table("reports")
    op.drop_index("ix_sos_events_status", table_name="sos_events")
    op.drop_table("sos_events")
    op.drop_table("devices")
    # pgcrypto extension left in place intentionally (may be shared/pre-existing).
