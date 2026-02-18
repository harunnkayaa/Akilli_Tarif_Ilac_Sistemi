from sqlalchemy.orm import Session
from sqlalchemy import select, delete

from app.core.models.user_disliked_ingredient import UserDislikedIngredient
from app.core.schemas.disliked import DislikedIngredientCreate

def list_disliked(db: Session, user_id):
    stmt = select(UserDislikedIngredient).where(UserDislikedIngredient.user_id == user_id)
    return db.execute(stmt).scalars().all()

def add_disliked(db: Session, user_id, payload: DislikedIngredientCreate):
    row = UserDislikedIngredient(
        user_id=user_id,
        ingredient_id=payload.ingredient_id,
        reason=payload.reason,
    )
    db.merge(row)  # varsa update, yoksa insert
    db.commit()
    return row

def remove_disliked(db: Session, user_id, ingredient_id: str):
    stmt = (
        delete(UserDislikedIngredient)
        .where(UserDislikedIngredient.user_id == user_id)
        .where(UserDislikedIngredient.ingredient_id == ingredient_id)
    )
    db.execute(stmt)
    db.commit()
