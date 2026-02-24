from __future__ import annotations

import uuid
from sqlalchemy import Column, Boolean, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from sqlalchemy.sql import func

from app.core.database import Base


class DrugSnoozePlan(Base):
    __tablename__ = "drug_snooze_plans"

    snooze_plan_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    intake_event_id = Column(
        UUID(as_uuid=True),
        ForeignKey("drug_intake_events.intake_event_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    remind_at = Column(TIMESTAMP(timezone=True), nullable=False, index=True)
    is_active = Column(Boolean, nullable=False, default=True)

    created_at = Column(
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=func.now(),
    )