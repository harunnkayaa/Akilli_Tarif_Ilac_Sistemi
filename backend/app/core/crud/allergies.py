from sqlalchemy.orm import Session
from sqlalchemy import select, delete

from app.core.models.user_allergy import UserAllergy
from app.core.schemas.allergy import AllergyCreate

def list_allergies(db: Session, user_id):
    stmt = select(UserAllergy).where(UserAllergy.user_id == user_id)
    return db.execute(stmt).scalars().all()

def add_allergy(db: Session, user_id, payload: AllergyCreate):
    row = UserAllergy(
        user_id=user_id,
        ingredient_id=payload.ingredient_id,
        reaction=payload.reaction,
        notes=payload.notes,
    )
    db.merge(row)
    db.commit()
    return row

def remove_allergy(db: Session, user_id, ingredient_id: str):
    stmt = (
        delete(UserAllergy)
        .where(UserAllergy.user_id == user_id)
        .where(UserAllergy.ingredient_id == ingredient_id)
    )
    db.execute(stmt)
    db.commit()
