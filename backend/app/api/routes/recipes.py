from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.core.database import get_db

router = APIRouter(prefix="/recipes", tags=["recipes"])


@router.get("/ingredients", response_model=list[str])
def search_recipe_ingredients(
    query: str = Query(default="", min_length=0, max_length=80),
    limit: int = Query(default=30, ge=1, le=50),
    db: Session = Depends(get_db),
):
    q = (query or "").strip()

    # jsonb array içinden Malzeme_Adi çek → distinct
    # NOT: burada ilike var ama SADECE autocomplete için (filtre için değil)
    sql = """
    SELECT DISTINCT elem->>'Malzeme_Adi' AS name
    FROM recipes r
    CROSS JOIN LATERAL jsonb_array_elements(r.malzemeler_json) AS elem
    WHERE elem ? 'Malzeme_Adi'
      AND ( :q = '' OR elem->>'Malzeme_Adi' ILIKE :pattern )
    ORDER BY name
    LIMIT :limit
    """

    pattern = f"%{q}%"
    rows = db.execute(
        text(sql),
        {"q": q, "pattern": pattern, "limit": limit},
    ).fetchall()

    return [r[0] for r in rows if r[0]]