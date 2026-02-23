from __future__ import annotations

import uuid
from sqlalchemy import Column, Date, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.core.database import Base


class UserDrug(Base):
    __tablename__ = "user_drugs"

    user_drug_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), nullable=False, index=True)

    drug_name = Column(Text, nullable=False)
    atc_code = Column(Text, nullable=True)
    drug_class = Column(Text, nullable=True)  # UI'dan istemiyorsun; DB'de kalsın, nullable.
    start_date = Column(Date, nullable=True)
    end_date = Column(Date, nullable=True)
    notes = Column(Text, nullable=True)

    schedules = relationship(
        "UserDrugSchedule",
        back_populates="user_drug",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )

    inventory = relationship(
        "DrugInventory",
        back_populates="user_drug",
        uselist=False,
        cascade="all, delete-orphan",
        passive_deletes=True,
    )