import logging
from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Body, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.core.database import get_db
from app.api.deps import get_current_user
from app.core.models.user import User
from app.core.models.daily_nutrient_total import DailyNutrientTotal
from app.core.config import BASE_URL
from app.core.schemas.recipe_chat import (
    RecipeChatSuggestRequest,
    RecipeChatSuggestResponse,
    RecipeCardOut,
    LLMSourcesOut,
    CookRecipeRequest,
    CookRecipeResponse,
    RecipeDetailResponse,
    RecipeIngredientOut,
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
    allow_partial_stock: bool = Query(False, description="True = stok olmadan mod: sadece stokta olan düşülür, meal_log ve besin toplamları tüm tarif için yazılır"),
    body: CookRecipeRequest | None = Body(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Tarif pişir: stok kontrolü, stok düşümü, meal_log, daily_nutrient_totals. allow_partial_stock=True ise eksik stok engel olmaz."""
    if not recipe_id or not recipe_id.strip():
        raise HTTPException(status_code=400, detail="recipe_id gerekli")
    add_pantry = None
    if body and body.add_pantry:
        add_pantry = [
            {"ingredient_id": i.ingredient_id, "quantity": i.quantity, "low_threshold": getattr(i, "low_threshold", None)}
            for i in body.add_pantry
        ]
    result = cook_recipe(
        db=db,
        user_id=current_user.user_id,
        recipe_id=recipe_id.strip(),
        servings_consumed=servings_consumed,
        notes=notes,
        allow_partial_stock=allow_partial_stock,
        add_pantry=add_pantry,
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
    """Malzeme adı önerisi: recipes.malzemeler_json içindeki Malzeme_Adi değerlerinden arar. Hata durumunda boş liste döner."""
    logger = logging.getLogger(__name__)
    q = (query or "").strip()

    try:
        # DISTINCT içinde ORDER BY select list'te olmalı; alt sorguda distinct, dışta LENGTH(name), name ile sırala
        sql = """
        SELECT name
        FROM (
            SELECT DISTINCT elem->>'Malzeme_Adi' AS name
            FROM recipes r
            CROSS JOIN LATERAL jsonb_array_elements(r.malzemeler_json) AS elem
            WHERE elem ? 'Malzeme_Adi'
              AND ( :q = '' OR elem->>'Malzeme_Adi' ILIKE :pattern )
        ) sub
        WHERE name IS NOT NULL AND name != ''
        ORDER BY LENGTH(name), name
        LIMIT :limit
        """
        pattern = f"%{q}%"
        rows = db.execute(
            text(sql),
            {"q": q, "pattern": pattern, "limit": limit},
        ).fetchall()
        return [r[0] for r in rows if r[0]]
    except Exception as e:
        logger.warning("search_recipe_ingredients failed (returning []): %s", e)
        return []


@router.get("/daily-totals")
def get_daily_totals(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Bugünkü günlük besin toplamları (sadece okuma). Home özet ekranı için."""
    row = (
        db.query(DailyNutrientTotal)
        .filter(
            DailyNutrientTotal.user_id == current_user.user_id,
            DailyNutrientTotal.day == date.today(),
        )
        .first()
    )
    if not row:
        return {
            "total_energy_kcal": None,
            "total_protein_g": None,
            "total_fat_g": None,
            "total_carbohydrate_g": None,
            "total_sodium_mg": None,
        }
    return {
        "total_energy_kcal": float(row.total_energy_kcal) if row.total_energy_kcal is not None else None,
        "total_protein_g": float(row.total_protein_g) if row.total_protein_g is not None else None,
        "total_fat_g": float(row.total_fat_g) if row.total_fat_g is not None else None,
        "total_carbohydrate_g": float(row.total_carbohydrate_g) if row.total_carbohydrate_g is not None else None,
        "total_sodium_mg": float(row.total_sodium_mg) if row.total_sodium_mg is not None else None,
    }


@router.get("/recent-meals")
def get_recent_meals(
    limit: int = Query(default=5, ge=1, le=10),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Son yapılan tarifler (meal_log + tarif adı). Home özet ekranı için."""
    rows = db.execute(
        text("""
            SELECT m.consumed_at, m.tarif_id, r.tarif_adi
            FROM meal_log m
            LEFT JOIN recipes r ON r.tarif_id = m.tarif_id
            WHERE m.user_id = :uid
            ORDER BY m.consumed_at DESC
            LIMIT :lim
        """),
        {"uid": current_user.user_id, "lim": limit},
    ).fetchall()
    return [
        {
            "tarif_id": r[1] or "",
            "tarif_adi": (r[2] or "Tarif").strip() or "Tarif",
            "consumed_at": r[0].isoformat() if r[0] else None,
        }
        for r in rows
    ]


@router.get("/{recipe_id}", response_model=RecipeDetailResponse)
def get_recipe_detail(
    recipe_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Tarif detayı: başlık, kategori, malzemeler, adımlar, görsel ve kalori bilgisi."""
    if not recipe_id or not recipe_id.strip():
        raise HTTPException(status_code=400, detail="recipe_id gerekli")

    row = db.execute(
        text(
            """
            SELECT tarif_id,
                   tarif_adi,
                   kategori,
                   porsiyon_sayisi,
                   toplam_kalori_kcal,
                   kaynak_url,
                   fotograf_url,
                   malzemeler_json,
                   tarif_adimlari
            FROM recipes
            WHERE tarif_id = :tid
            """
        ),
        {"tid": recipe_id.strip()},
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Tarif bulunamadı.")

    malzemeler = row[7] or []
    ingredients: list[RecipeIngredientOut] = []
    if isinstance(malzemeler, list):
        for elem in malzemeler:
            if not isinstance(elem, dict):
                continue
            name = str(
                elem.get("Malzeme_Adi")
                or elem.get("malzeme_adi")
                or ""
            ).strip()
            if not name:
                continue
            unit = elem.get("Birim") or elem.get("birim")
            amount_raw = elem.get("Standart_Miktar") or elem.get("standart_miktar")
            try:
                amount = float(amount_raw) if amount_raw is not None else None
            except Exception:
                amount = None
            display_amount = elem.get("Tarif_Olcum") or elem.get("tarif_olcum")
            ingredients.append(
                RecipeIngredientOut(
                    name=name,
                    unit=str(unit).strip() if isinstance(unit, str) and unit.strip() else None,
                    amount=amount,
                    display_amount=str(display_amount).strip() if display_amount else None,
                )
            )

    total = row[4]
    servings = row[3]
    calories_per_serving = None
    try:
        if total is not None and servings not in (None, 0):
            calories_per_serving = float(total) / float(servings)
    except Exception:
        calories_per_serving = None

    fotograf_url = row[6]
    image_url = None
    if fotograf_url:
        # DB yalnızca relatif yolu tutar (örn. /static/recipes/TR0001.jpg)
        image_url = f"{BASE_URL}{fotograf_url}"

    return RecipeDetailResponse(
        recipe_id=str(row[0]),
        title=row[1] or "",
        category=row[2],
        servings=servings,
        total_calories_kcal=float(total) if total is not None else None,
        calories_per_serving_kcal=calories_per_serving,
        source_url=row[5],
        image_url=image_url,
        steps=row[8],
        ingredients=ingredients,
    )