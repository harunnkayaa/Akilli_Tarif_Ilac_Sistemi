from uuid import UUID

from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.core.database import get_db
from app.api.deps import get_current_user
from app.core.models.user import User
from app.core.schemas.recipe_chat import (
    RecipeChatSuggestRequest,
    RecipeChatSuggestResponse,
    RecipeCardOut,
    LLMSourcesOut,
    CookRecipeResponse,
)
from app.core.services.chat_service import suggest_recipes
from app.core.services.cook_service import cook_recipe

router = APIRouter(prefix="/recipes", tags=["recipes"])


@router.post("/chat/suggest", response_model=RecipeChatSuggestResponse)
def suggest_recipes_endpoint(
    body: RecipeChatSuggestRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Tarif sohbet önerisi. Semantic retrieval (OpenAI embedding) kullanır; embedding hata verirse ILIKE fallback."""
    session_id = None
    if body.session_id:
        try:
            session_id = UUID(body.session_id)
        except ValueError:
            pass
    result = suggest_recipes(
        db=db,
        user_id=current_user.user_id,
        message=body.message.strip(),
        session_id=session_id,
        mode=body.mode,
        query_embedding=None,
    )
    return RecipeChatSuggestResponse(
        session_id=result["session_id"],
        assistant_text=result["assistant_text"],
        cards=[RecipeCardOut(**c) for c in result["cards"]],
        llm_sources=LLMSourcesOut(**result["llm_sources"]) if result.get("llm_sources") else None,
    )


@router.post("/{recipe_id}/cook", response_model=CookRecipeResponse)
def cook_recipe_endpoint(
    recipe_id: str,
    servings_consumed: float = 1.0,
    notes: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Tarif pişir: stok kontrolü, stok düşümü, meal_log, daily_nutrient_totals güncellemesi."""
    if not recipe_id or not recipe_id.strip():
        raise HTTPException(status_code=400, detail="recipe_id gerekli")
    result = cook_recipe(
        db=db,
        user_id=current_user.user_id,
        recipe_id=recipe_id.strip(),
        servings_consumed=servings_consumed,
        notes=notes,
    )
    if not result["success"] and result.get("error") == "Tarif bulunamadı.":
        raise HTTPException(status_code=404, detail="Tarif bulunamadı.")
    return CookRecipeResponse(
        success=result["success"],
        error=result.get("error"),
        missing=result.get("missing"),
        daily_nutrient_totals=result.get("daily_nutrient_totals"),
    )


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