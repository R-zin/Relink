"""client_msg_id for idempotent multi-relay flushing

Phase 3 (plans/phase_3.md §6): every mesh message carries a client-generated
UUID (`MeshMessage.id`). Multiple offline relays may each flush the SAME message
to the backend once they reach connectivity. Storing that UUID as a UNIQUE
column lets the ingest endpoints treat a duplicate flush as a no-op (return 200
with the existing row) instead of inserting a duplicate row or failing with a
500 on the unique constraint.

Adds nullable UNIQUE `client_msg_id` to `sos_events` and `reports`.

Revision ID: 0002
Revises: 0001
Create Date: 2026-09-05
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "sos_events",
        sa.Column("client_msg_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_unique_constraint("uq_sos_events_client_msg_id", "sos_events", ["client_msg_id"])

    op.add_column(
        "reports",
        sa.Column("client_msg_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_unique_constraint("uq_reports_client_msg_id", "reports", ["client_msg_id"])


def downgrade() -> None:
    op.drop_constraint("uq_reports_client_msg_id", "reports", type_="unique")
    op.drop_column("reports", "client_msg_id")
    op.drop_constraint("uq_sos_events_client_msg_id", "sos_events", type_="unique")
    op.drop_column("sos_events", "client_msg_id")
