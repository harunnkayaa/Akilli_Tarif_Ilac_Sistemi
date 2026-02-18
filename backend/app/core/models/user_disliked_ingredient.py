from sqlalchemy import Text, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

class UserDislikedIngredient(Base):
    __tablename__ = "user_disliked_ingredients"

    # Composite PK: aynı ingredient'i 2 kere eklemesin
    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.user_id", ondelete="CASCADE"),
        primary_key=True,
    )
    ingredient_id: Mapped[str] = mapped_column(
        Text,
        ForeignKey("ingredients.id", ondelete="CASCADE"),
        primary_key=True,
    )
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
