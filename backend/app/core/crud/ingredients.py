from sqlalchemy.orm import Session
from sqlalchemy import select, func, or_, cast, Text

from app.core.models.ingredient import Ingredient


def get_ingredient(db: Session, ingredient_id: str):
    stmt = select(Ingredient).where(Ingredient.id == ingredient_id)
    return db.execute(stmt).scalars().first()


def search_ingredients(db: Session, query: str, limit: int = 20):
    q = (query or "").strip()
    if not q:
        return []

    pattern = f"%{q.lower()}%"

    def ua(col):
        return func.unaccent(func.lower(cast(col, Text)))

    stmt = (
        select(Ingredient.id, Ingredient.canonical_name_tr)
        .where(
            or_(
                ua(Ingredient.canonical_name_tr).like(func.unaccent(pattern)),
                ua(Ingredient.synonyms_tr).like(func.unaccent(pattern)),
                ua(Ingredient.allergen_tags).like(func.unaccent(pattern)),
            )
        )
        .order_by(Ingredient.canonical_name_tr.asc())
        .limit(limit)
    )

    rows = db.execute(stmt).all()
    return [{"id": r.id, "canonical_name_tr": r.canonical_name_tr} for r in rows]
