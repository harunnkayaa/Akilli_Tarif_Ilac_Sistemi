from __future__ import annotations

from sqlalchemy import Column, Integer, Text, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship

from app.core.database import Base


class DrugInventory(Base):
    __tablename__ = "drug_inventory"

    # 1-1 garanti: PK = FK (DB constraint ile bunu enforce edeceksin)
    user_drug_id = Column(
        UUID(as_uuid=True),
        ForeignKey("user_drugs.user_drug_id", ondelete="CASCADE"),
        primary_key=True,
    )

    quantity = Column(Integer, nullable=False, default=0)
    unit = Column(Text, nullable=True)  # "tablet", "kapsül"...
    low_threshold = Column(Integer, nullable=False, default=0)

    last_updated = Column(
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    user_drug = relationship("UserDrug", back_populates="inventory")