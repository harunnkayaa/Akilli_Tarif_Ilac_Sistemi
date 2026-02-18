from sqlalchemy.orm import Session
from sqlalchemy import select, delete, func
from fastapi import HTTPException

from app.core.models.user_disease import UserDisease
from app.core.schemas.disease import DiseaseCreate
from app.core.models.disease_nutrient_limit import DiseaseNutrientLimit

def list_diseases(db: Session, user_id):
    stmt = select(UserDisease).where(UserDisease.user_id == user_id)
    return db.execute(stmt).scalars().all()

def _is_known_disease(db: Session, name: str) -> bool:
    stmt = (
        select(func.count())
        .select_from(DiseaseNutrientLimit)
        .where(DiseaseNutrientLimit.disease_name == name)
    )
    return (db.execute(stmt).scalar() or 0) > 0

def add_disease(db: Session, user_id, payload: DiseaseCreate):
    name = payload.disease_name.strip()

    if not _is_known_disease(db, name):
        raise HTTPException(
            status_code=422,
            detail="Bu hastalık için Dünya Sağlık Örgütü (WHO) standartlarına göre besin değeri sınırı bulunmamaktadır.",
        )

    row = UserDisease(
        user_id=user_id,
        disease_name=name,
        diagnosed_at=payload.diagnosed_at,
        notes=payload.notes,
    )
    db.merge(row)
    db.commit()
    return row

def remove_disease(db: Session, user_id, disease_name: str):
    stmt = (
        delete(UserDisease)
        .where(UserDisease.user_id == user_id)
        .where(UserDisease.disease_name == disease_name)
    )
    db.execute(stmt)
    db.commit()
