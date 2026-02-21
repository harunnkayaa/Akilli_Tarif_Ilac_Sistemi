from sqlalchemy import Text, BigInteger, Float
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class Ingredient(Base):
    __tablename__ = "ingredients"

    # DB'de id TEXT (ör: "TR_0001")
    id: Mapped[str] = mapped_column(Text, primary_key=True)

    canonical_name_tr: Mapped[str | None] = mapped_column(Text, nullable=True, index=True)
    english_name: Mapped[str | None] = mapped_column(Text, nullable=True)

    # arama için kritik alanlar
    synonyms_tr: Mapped[str | None] = mapped_column(Text, nullable=True)
    allergen_tags: Mapped[str | None] = mapped_column(Text, nullable=True)
    risk_tags: Mapped[str | None] = mapped_column(Text, nullable=True)

    # opsiyonel
    fdc_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    unit_base: Mapped[str | None] = mapped_column(Text, nullable=True)

    # besin değerleri (opsiyonel)
    energy_kcal: Mapped[float | None] = mapped_column(Float, nullable=True)
    protein_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    total_fat_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    saturated_fat_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    monounsaturated_fat_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    polyunsaturated_fat_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    trans_fat_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    carbohydrate_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    sugars_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    added_sugars_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    fiber_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    water_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    sodium_mg: Mapped[float | None] = mapped_column(Float, nullable=True)

    # kaynak alanların varsa bırak, yoksa kaldır
    source: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_updated: Mapped[str | None] = mapped_column(Text, nullable=True)