from sqlalchemy.orm import Session
from sqlalchemy import select, delete, func
from app.core.models.user_allergy import UserAllergy
from app.core.models.ingredient import Ingredient
from app.core.schemas.allergy import AllergyCreate


def _row_to_out(row: UserAllergy, ing_name: str | None):
    display = ing_name or row.raw_text or (row.ingredient_id or "-")
    return {
        "id": row.id,
        "ingredient_id": row.ingredient_id,
        "raw_text": row.raw_text,
        "is_custom": row.is_custom,
        "reaction": row.reaction,
        "notes": row.notes,
        "display_name": display,
    }


def list_allergies(db: Session, user_id):
    stmt = (
        select(UserAllergy, Ingredient.canonical_name_tr)
        .outerjoin(Ingredient, Ingredient.id == UserAllergy.ingredient_id)
        .where(UserAllergy.user_id == user_id)
        .order_by(UserAllergy.id.desc())
    )
    rows = db.execute(stmt).all()
    return [_row_to_out(r[0], r[1]) for r in rows]


def add_allergy(db: Session, user_id, payload: AllergyCreate):
    # Duplicate kontrolü:
    if payload.ingredient_id:
        exists_stmt = select(func.count()).select_from(UserAllergy).where(
            UserAllergy.user_id == user_id,
            UserAllergy.ingredient_id == payload.ingredient_id,
        )
        if db.execute(exists_stmt).scalar_one() > 0:
            raise ValueError("already_exists")

        row = UserAllergy(
            user_id=user_id,
            ingredient_id=payload.ingredient_id,
            raw_text=None,
            is_custom=False,
            reaction=payload.reaction,
            notes=payload.notes,
        )
        db.add(row)
        db.commit()
        db.refresh(row)

        ing_name = db.execute(
            select(Ingredient.canonical_name_tr).where(Ingredient.id == row.ingredient_id)
        ).scalar_one_or_none()

        return _row_to_out(row, ing_name)

    # raw_text ile ekleme (tarif malzemesi / custom)
    raw = payload.raw_text.strip()
    # Aynı raw_text tekrar eklenmesin (case-insensitive)
    exists_stmt = select(func.count()).select_from(UserAllergy).where(
        UserAllergy.user_id == user_id,
        UserAllergy.ingredient_id.is_(None),
        func.lower(UserAllergy.raw_text) == func.lower(raw),
    )
    if db.execute(exists_stmt).scalar_one() > 0:
        raise ValueError("already_exists")

    row = UserAllergy(
        user_id=user_id,
        ingredient_id=None,
        raw_text=raw,
        is_custom=True,
        reaction=payload.reaction,
        notes=payload.notes,
    )
    db.add(row)
    db.commit()
    db.refresh(row)

    return _row_to_out(row, None)


def remove_allergy(db: Session, user_id, allergy_id: int):
    stmt = delete(UserAllergy).where(
        UserAllergy.user_id == user_id,
        UserAllergy.id == allergy_id,
    )
    db.execute(stmt)
    db.commit()