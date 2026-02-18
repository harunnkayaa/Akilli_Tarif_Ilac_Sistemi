"""Health router."""
from fastapi import APIRouter, Query, Depends
from sqlalchemy.orm import Session
from sqlalchemy import select, distinct

from app.core.database import get_db
from app.core.models.disease_nutrient_limit import DiseaseNutrientLimit

router = APIRouter(prefix="/health", tags=["health"])


@router.get("")
def health():
    return {"status": "ok"}


@router.get("/diseases", response_model=list[str])
def search_diseases(
    query: str = Query(default="", min_length=0, max_length=80),
    db: Session = Depends(get_db),
):
    q = query.strip()
    stmt = select(distinct(DiseaseNutrientLimit.disease_name))
    if q:
        stmt = stmt.where(DiseaseNutrientLimit.disease_name.ilike(f"%{q}%"))
    stmt = stmt.order_by(DiseaseNutrientLimit.disease_name).limit(30)
    return db.execute(stmt).scalars().all()
