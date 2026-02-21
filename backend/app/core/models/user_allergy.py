from sqlalchemy import Text, ForeignKey, Boolean, BigInteger
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class UserAllergy(Base):
    __tablename__ = "user_allergies"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)

    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.user_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # ingredient_id opsiyonel (senin tabloda NULL olabiliyor)
    ingredient_id: Mapped[str | None] = mapped_column(
        Text,
        ForeignKey("ingredients.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )

    raw_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_custom: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    reaction: Mapped[str | None] = mapped_column(Text, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    # tablonda "note" diye ekstra kolon varsa kalsın, yoksa kaldır
    note: Mapped[str | None] = mapped_column(Text, nullable=True)