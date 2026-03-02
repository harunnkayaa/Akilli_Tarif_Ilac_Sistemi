"""
Tarif pişir: stok kontrolü, stok düşümü, meal_log, daily_nutrient_totals güncellemesi.
"""
from __future__ import annotations

import uuid
from datetime import date
from typing import Dict, Any

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.models.pantry_items import PantryItem
from app.core.models.meal_log import MealLog
from app.core.models.daily_nutrient_total import DailyNutrientTotal
from app.core.services.rules_engine import check_recipe_stock


def _get_recipe(db: Session, tarif_id: str) -> Dict[str, Any] | None:
    row = db.execute(
        text("""
            SELECT tarif_id, tarif_adi, porsiyon_sayisi, toplam_kalori_kcal, malzemeler_json
            FROM recipes WHERE tarif_id = :tid
        """),
        {"tid": tarif_id},
    ).fetchone()
    if not row:
        return None
    return {
        "tarif_id": row[0],
        "tarif_adi": row[1],
        "porsiyon_sayisi": row[2],
        "toplam_kalori_kcal": row[3],
        "malzemeler_json": row[4],
    }


def _deduct_pantry(db: Session, user_id, deductions: list[Dict[str, Any]]) -> None:
    """deductions: [{"ingredient_id": "...", "quantity": float}, ...]"""
    for d in deductions:
        ing_id = d.get("ingredient_id")
        qty = float(d.get("quantity") or 0)
        if not ing_id or qty <= 0:
            continue
        item = (
            db.query(PantryItem)
            .filter(
                PantryItem.user_id == user_id,
                PantryItem.ingredient_id == ing_id,
            )
            .first()
        )
        if not item:
            continue
        new_qty = float(item.quantity or 0) - qty
        item.quantity = max(0, new_qty)


def _update_daily_totals(
    db: Session,
    user_id,
    day: date,
    added_energy_kcal: float,
) -> Dict[str, Any]:
    """Tariften eklenen kaloriyi daily_nutrient_totals'a ekle; güncel değerleri döndür."""
    row = (
        db.query(DailyNutrientTotal)
        .filter(
            DailyNutrientTotal.user_id == user_id,
            DailyNutrientTotal.day == day,
        )
        .first()
    )
    if not row:
        row = DailyNutrientTotal(
            user_id=user_id,
            day=day,
            total_energy_kcal=added_energy_kcal,
            total_protein_g=None,
            total_fat_g=None,
            total_carbohydrate_g=None,
            total_sodium_mg=None,
        )
        db.add(row)
    else:
        prev = float(row.total_energy_kcal or 0)
        row.total_energy_kcal = prev + added_energy_kcal
    db.flush()
    return {
        "total_energy_kcal": float(row.total_energy_kcal) if row.total_energy_kcal is not None else None,
        "total_protein_g": float(row.total_protein_g) if row.total_protein_g is not None else None,
        "total_fat_g": float(row.total_fat_g) if row.total_fat_g is not None else None,
        "total_carbohydrate_g": float(row.total_carbohydrate_g) if row.total_carbohydrate_g is not None else None,
        "total_sodium_mg": float(row.total_sodium_mg) if row.total_sodium_mg is not None else None,
    }


def cook_recipe(
    db: Session,
    user_id,
    recipe_id: str,
    servings_consumed: float = 1.0,
    notes: str | None = None,
) -> Dict[str, Any]:
    """
    Stok kontrolü -> yetersizse hata; yeterliyse stok düş, meal_log ekle, daily_nutrient_totals güncelle.
    Dönüş: { "success": True, "daily_nutrient_totals": { ... } }
    """
    recipe = _get_recipe(db, recipe_id)
    if not recipe:
        return {"success": False, "error": "Tarif bulunamadı.", "daily_nutrient_totals": None}

    stock_result = check_recipe_stock(db, user_id, recipe.get("malzemeler_json"))
    if not stock_result["ok"]:
        return {
            "success": False,
            "error": "Stok yetersiz (zorunlu malzemeler eksik).",
            "missing": stock_result["missing"],
            "daily_nutrient_totals": None,
        }

    _deduct_pantry(db, user_id, stock_result["deductions"])

    log_id = uuid.uuid4()
    db.add(MealLog(
        log_id=log_id,
        user_id=user_id,
        tarif_id=recipe_id,
        servings_consumed=servings_consumed,
        notes=notes,
    ))

    porsiyon = recipe.get("porsiyon_sayisi") or 1
    toplam_kalori = recipe.get("toplam_kalori_kcal")
    cal_per_serving = (float(toplam_kalori) / porsiyon * servings_consumed) if toplam_kalori is not None and porsiyon else 0.0
    today = date.today()
    totals = _update_daily_totals(db, user_id, today, cal_per_serving)

    db.commit()
    return {"success": True, "daily_nutrient_totals": totals}
