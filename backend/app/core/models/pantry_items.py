from sqlalchemy import Column, String, Date, Numeric, TIMESTAMP, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func

from app.core.database import Base


class PantryItem(Base):
    __tablename__ = "pantry_items"

    user_id = Column(UUID(as_uuid=True), primary_key=True, index=True)
    ingredient_id = Column(Text, primary_key=True, nullable=False)  # ✅ PK yap

    quantity = Column(Numeric(10, 2), nullable=False, default=0)
    unit = Column(String, nullable=True)
    expires_at = Column(Date, nullable=True)
    low_threshold = Column(Numeric(10, 2), nullable=True)
    updated_at = Column(
        TIMESTAMP(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )