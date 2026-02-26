import uuid
from sqlalchemy import Column, String, Boolean, Numeric, TIMESTAMP, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func

from app.core.database import Base


class ShoppingListItem(Base):
    __tablename__ = "shopping_list_items"

    item_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), index=True, nullable=False)

    ingredient_id = Column(Text, nullable=True)  # artık serbest metin (istersen hiç kullanma)
    item_text = Column(String, nullable=True)

    target_qty = Column(Numeric(10, 2), nullable=True)
    unit = Column(String, nullable=True)

    is_checked = Column(Boolean, nullable=False, default=False)

    created_at = Column(TIMESTAMP(timezone=True), nullable=False, server_default=func.now())