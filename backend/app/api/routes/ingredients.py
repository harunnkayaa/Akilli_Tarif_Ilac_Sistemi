from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.schemas.ingredient import IngredientOut
from app.core.crud.ingredients import search_ingredients, get_ingredient

router = APIRouter(prefix="/ingredients", tags=["ingredients"])


@router.get("", response_model=list[IngredientOut])
def search(
    query: str = Query(default="", min_length=0),
    limit: int = Query(default=20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    return search_ingredients(db, query=query, limit=limit)


@router.get("/{ingredient_id}", response_model=IngredientOut)
def by_id(ingredient_id: str, db: Session = Depends(get_db)):
    row = get_ingredient(db, ingredient_id)
    if not row:
        raise HTTPException(status_code=404, detail="ingredient not found")
    return row
