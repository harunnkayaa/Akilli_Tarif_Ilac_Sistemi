from sqlalchemy import Text, BigInteger, Float
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base

class DiseaseNutrientLimit(Base):
    __tablename__ = "disease_nutrient_limits"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    disease_name: Mapped[str] = mapped_column(Text, nullable=False)
    nutrient_tag: Mapped[str] = mapped_column(Text, nullable=False)
    limit_type: Mapped[str] = mapped_column(Text, nullable=False)

    value: Mapped[float | None] = mapped_column(Float, nullable=True)
    unit: Mapped[str | None] = mapped_column(Text, nullable=True)
    condition_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_primary: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_url: Mapped[str | None] = mapped_column(Text, nullable=True)
