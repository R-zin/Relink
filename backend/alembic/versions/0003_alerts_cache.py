"""alerts_cache table for NDMA Sachet CAP/RSS alerts

Phase 4 (plans/phase_4.md §4): the Sachet RSS poller parses official NDMA CAP
alerts and upserts them here. `GET /alerts` serves the cached rows so the app
and dashboard never depend on the external feed being up at request time.

Revision ID: 0003
Revises: 0002
Create Date: 2026-09-05
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "alerts_cache",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        # External CAP identifier; UNIQUE for idempotent upsert on re-poll.
        sa.Column("cap_identifier", sa.Text(), nullable=False),
        sa.Column("source", sa.Text(), nullable=False, server_default="sachet"),
        sa.Column("state", sa.Text(), nullable=False),
        sa.Column("event", sa.Text(), nullable=True),
        sa.Column("headline", sa.Text(), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("instruction", sa.Text(), nullable=True),
        # CAP severity verbatim (Extreme/Severe/Moderate/Minor/Unknown) or the
        # demo color tag (Red) for test alerts.
        sa.Column("severity", sa.Text(), nullable=True),
        sa.Column("urgency", sa.Text(), nullable=True),
        sa.Column("certainty", sa.Text(), nullable=True),
        sa.Column("area_desc", sa.Text(), nullable=True),
        sa.Column("sender", sa.Text(), nullable=True),
        sa.Column("effective", sa.DateTime(timezone=True), nullable=True),
        sa.Column("onset", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires", sa.DateTime(timezone=True), nullable=True),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_test", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("cap_identifier", name="uq_alerts_cache_cap_identifier"),
    )
    op.create_index("ix_alerts_cache_state_issued_at", "alerts_cache", ["state", sa.text("issued_at DESC")])


def downgrade() -> None:
    op.drop_index("ix_alerts_cache_state_issued_at", table_name="alerts_cache")
    op.drop_table("alerts_cache")
