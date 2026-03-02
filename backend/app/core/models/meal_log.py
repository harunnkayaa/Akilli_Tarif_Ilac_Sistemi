from sqlalchemy import Column, Text, Numeric, TIMESTAMP, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func

from app.core.database import Base


class MealLog(Base):
    __tablename__ = "meal_log"

    log_id = Column(UUID(as_uuid=True), primary_key=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False, index=True)
    tarif_id = Column(Text, ForeignKey("recipes.tarif_id", ondelete="SET NULL"), nullable=True, index=True)
    consumed_at = Column(TIMESTAMP(timezone=True), nullable=False, server_default=func.now())
    servings_consumed = Column(Numeric(10, 2), nullable=False)
    notes = Column(Text, nullable=True)
