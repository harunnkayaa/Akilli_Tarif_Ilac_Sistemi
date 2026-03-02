from sqlalchemy import Column, Date, Numeric, TIMESTAMP, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func

from app.core.database import Base


class DailyNutrientTotal(Base):
    __tablename__ = "daily_nutrient_totals"

    user_id = Column(UUID(as_uuid=True), ForeignKey("users.user_id", ondelete="CASCADE"), primary_key=True)
    day = Column(Date, primary_key=True)
    total_energy_kcal = Column(Numeric(12, 2), nullable=True)
    total_protein_g = Column(Numeric(12, 2), nullable=True)
    total_fat_g = Column(Numeric(12, 2), nullable=True)
    total_carbohydrate_g = Column(Numeric(12, 2), nullable=True)
    total_sodium_mg = Column(Numeric(12, 2), nullable=True)
    updated_at = Column(TIMESTAMP(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())
