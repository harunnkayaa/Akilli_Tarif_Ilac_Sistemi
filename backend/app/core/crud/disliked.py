from sqlalchemy.orm import Session
from sqlalchemy import select, delete, func

from app.core.models.user_disliked_ingredient import UserDislikedIngredient
from app.core.schemas.disliked import DislikedIngredientCreate


def list_disliked(db: Session, user_id):
    stmt = (
        select(UserDislikedIngredient)
        .where(UserDislikedIngredient.user_id == user_id)
        .order_by(UserDislikedIngredient.id.desc())
    )
    rows = db.execute(stmt).scalars().all()
    return [
        {
            "id": r.id,
            "display_name": (r.raw_text or r.free_text or "").strip() or (r.ingredient_id or ""),
            "reason": r.reason,
        }
        for r in rows
    ]


def add_disliked(db: Session, user_id, payload: DislikedIngredientCreate):
    raw = payload.raw_text.strip()
    if not raw:
        raise ValueError("empty")

    # duplicate: aynı raw_text'i 2 kere ekleme (case-insensitive)
    dup_stmt = select(UserDislikedIngredient).where(
        UserDislikedIngredient.user_id == user_id,
        func.lower(func.coalesce(UserDislikedIngredient.raw_text, "")) == func.lower(raw),
    )
    if db.execute(dup_stmt).scalar_one_or_none():
        raise ValueError("already_exists")

    row = UserDislikedIngredient(
        user_id=user_id,
        raw_text=raw,
        is_custom=False,
        reason=payload.reason,
    )
    db.add(row)
    db.commit()
    db.refresh(row)

    return {"id": row.id, "display_name": row.raw_text, "reason": row.reason}


def remove_disliked(db: Session, user_id, disliked_id: int):
    stmt = (
        delete(UserDislikedIngredient)
        .where(UserDislikedIngredient.user_id == user_id)
        .where(UserDislikedIngredient.id == disliked_id)
    )
    db.execute(stmt)
    db.commit()