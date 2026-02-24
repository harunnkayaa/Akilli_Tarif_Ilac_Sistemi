from __future__ import annotations

import uuid
from sqlalchemy import Column, Integer, Text, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship

from app.core.database import Base


class DrugIntakeEvent(Base):
    __tablename__ = "drug_intake_events"

    intake_event_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    user_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    user_drug_id = Column(
        UUID(as_uuid=True),
        ForeignKey("user_drugs.user_drug_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # client tarafındaki deterministic id (stableId + action + timestamp vs)
    client_event_id = Column(Text, nullable=False)

    # TAKEN / SNOOZE / SKIP
    action = Column(Text, nullable=False)

    # hangi planlı occurrence içindi (client gönderir)
    scheduled_at = Column(TIMESTAMP(timezone=True), nullable=True)

    # TAKEN ise düşülen doz (int)
    dose = Column(Integer, nullable=False, default=1)

    created_at = Column(
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    user_drug = relationship("UserDrug")

    __table_args__ = (
        UniqueConstraint("user_id", "client_event_id", name="uq_intake_user_client_event"),
    )