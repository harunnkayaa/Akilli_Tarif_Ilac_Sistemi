from sqlalchemy import Text, ForeignKey, Boolean, BigInteger
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class UserDislikedIngredient(Base):
    __tablename__ = "user_disliked_ingredients"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.user_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    ingredient_id: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
    )

    reason: Mapped[str | None] = mapped_column(Text, nullable=True)

    raw_text: Mapped[str | None] = mapped_column(Text, nullable=True)

    is_custom: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    free_text: Mapped[str | None] = mapped_column(Text, nullable=True)