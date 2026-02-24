import uuid
from sqlalchemy import Column, Integer, Boolean, Time, Text, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from app.core.database import Base


class UserDrugSchedule(Base):
    __tablename__ = "user_drug_schedule"

    schedule_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_drug_id = Column(
        UUID(as_uuid=True),
        ForeignKey("user_drugs.user_drug_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    dose_text = Column(Text, nullable=True)
    time_of_day = Column(Time, nullable=False)
    days_mask = Column(Integer, nullable=False, default=127)
    is_active = Column(Boolean, nullable=False, default=True)

    user_drug = relationship("UserDrug", back_populates="schedules")