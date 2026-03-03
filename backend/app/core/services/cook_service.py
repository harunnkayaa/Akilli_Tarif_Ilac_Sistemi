"""
Tarif pişir: stok kontrolü, stok düşümü, meal_log, daily_nutrient_totals güncellemesi.
allow_partial_stock=True (stok olmadan mod): sadece stokta olan malzemeden düşer; meal_log + daily_nutrient_totals tüm tarif için doldurulur.
"""
from __future__ import annotations

import uuid
from datetime import date
from typing import Dict, Any, List, Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.models.pantry_items import PantryItem
from app.core.models.meal_log import MealLog
from app.core.models.daily_nutrient_total import DailyNutrientTotal
from app.core.models.ingredient import Ingredient
from app.core.services.rules_engine import check_recipe_stock, _pantry_name_matches_recipe_ingredient


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
    added_energy_kcal: float = 0.0,
    added_protein_g: Optional[float] = None,
    added_fat_g: Optional[float] = None,
    added_carbohydrate_g: Optional[float] = None,
    added_sodium_mg: Optional[float] = None,
) -> Dict[str, Any]:
    """Tariften eklenen besin değerlerini daily_nutrient_totals'a ekle; güncel değerleri döndür."""
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
            total_energy_kcal=added_energy_kcal or None,
            total_protein_g=added_protein_g,
            total_fat_g=added_fat_g,
            total_carbohydrate_g=added_carbohydrate_g,
            total_sodium_mg=added_sodium_mg,
        )
        db.add(row)
    else:
        if added_energy_kcal is not None:
            row.total_energy_kcal = float(row.total_energy_kcal or 0) + added_energy_kcal
        if added_protein_g is not None:
            row.total_protein_g = float(row.total_protein_g or 0) + added_protein_g
        if added_fat_g is not None:
            row.total_fat_g = float(row.total_fat_g or 0) + added_fat_g
        if added_carbohydrate_g is not None:
            row.total_carbohydrate_g = float(row.total_carbohydrate_g or 0) + added_carbohydrate_g
        if added_sodium_mg is not None:
            row.total_sodium_mg = float(row.total_sodium_mg or 0) + added_sodium_mg
    db.flush()
    return {
        "total_energy_kcal": float(row.total_energy_kcal) if row.total_energy_kcal is not None else None,
        "total_protein_g": float(row.total_protein_g) if row.total_protein_g is not None else None,
        "total_fat_g": float(row.total_fat_g) if row.total_fat_g is not None else None,
        "total_carbohydrate_g": float(row.total_carbohydrate_g) if row.total_carbohydrate_g is not None else None,
        "total_sodium_mg": float(row.total_sodium_mg) if row.total_sodium_mg is not None else None,
    }


def _amount_to_grams(miktar: float, birim: Optional[str]) -> float:
    """Standart_Miktar + Birim -> gram (ingredients tablosu 100g bazlı)."""
    if birim is None:
        return miktar
    b = str(birim).strip().lower()
    if b in ("g", "gr", "gram"):
        return miktar
    if b in ("ml", "ml.", "mililitre"):
        return miktar  # ml'yi gram gibi kabul (yoğunluk 1)
    if b in ("adet", "adet.", "piece"):
        return miktar * 50.0  # kabaca 50g/adet
    return miktar


def _compute_recipe_nutrients_from_ingredients(
    db: Session,
    malzemeler_json: Any,
) -> Dict[str, float]:
    """
    Tarif malzemelerini ingredients tablosu ile eşleştirir (isim eşleşmesi);
    her malzeme için Standart_Miktar/Birim -> gram, ingredients'deki 100g bazlı değerlerle çarpıp toplar.
    """
    out = {
        "energy_kcal": 0.0,
        "protein_g": 0.0,
        "total_fat_g": 0.0,
        "carbohydrate_g": 0.0,
        "sodium_mg": 0.0,
    }
    if not malzemeler_json or not isinstance(malzemeler_json, list):
        return out

    ingredients_rows = db.query(
        Ingredient.id,
        Ingredient.canonical_name_tr,
        Ingredient.synonyms_tr,
        Ingredient.energy_kcal,
        Ingredient.protein_g,
        Ingredient.total_fat_g,
        Ingredient.carbohydrate_g,
        Ingredient.sodium_mg,
    ).all()

    for elem in malzemeler_json:
        if not isinstance(elem, dict):
            continue
        name = elem.get("Malzeme_Adi") or elem.get("malzeme_adi")
        miktar = elem.get("Standart_Miktar")
        birim = elem.get("Birim") or elem.get("birim")
        if name is None or miktar is None:
            continue
        try:
            need_val = float(miktar)
        except (TypeError, ValueError):
            continue
        if need_val <= 0:
            continue
        name_str = str(name).strip()
        amount_g = _amount_to_grams(need_val, birim)

        row = None
        for r in ingredients_rows:
            ing_id, canonical, synonyms, e_kcal, p_g, f_g, c_g, s_mg = r
            if _pantry_name_matches_recipe_ingredient(canonical or "", name_str):
                row = r
                break
            if synonyms:
                for syn in (s.strip() for s in str(synonyms).split(",") if s.strip()):
                    if _pantry_name_matches_recipe_ingredient(syn, name_str):
                        row = r
                        break
                if row is not None:
                    break
        if row is None:
            continue
        _ing_id, _canonical, _synonyms, e_kcal, p_g, f_g, c_g, s_mg = row

        factor = amount_g / 100.0
        out["energy_kcal"] += (float(e_kcal or 0)) * factor
        out["protein_g"] += (float(p_g or 0)) * factor
        out["total_fat_g"] += (float(f_g or 0)) * factor
        out["carbohydrate_g"] += (float(c_g or 0)) * factor
        out["sodium_mg"] += (float(s_mg or 0)) * factor

    return out


def cook_recipe(
    db: Session,
    user_id,
    recipe_id: str,
    servings_consumed: float = 1.0,
    notes: str | None = None,
    allow_partial_stock: bool = False,
    add_pantry: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """
    Stok kontrolü -> allow_partial_stock=False ve yetersizse hata döner.
    allow_partial_stock=True (stok olmadan mod): sadece stokta olan malzemeden düşülür, meal_log + daily_nutrient_totals tüm tarif için yazılır.
    add_pantry: [{"ingredient_id": str, "quantity": float}, ...] verilirse önce stoka eklenir, sonra cook yapılır.
    Dönüş: { "success": True, "daily_nutrient_totals": { ... } } veya success=False, missing listesi.
    """
    from app.core.crud import kitchen as kitchen_crud

    recipe = _get_recipe(db, recipe_id)
    if not recipe:
        return {"success": False, "error": "Tarif bulunamadı.", "missing": None, "daily_nutrient_totals": None}

    if add_pantry:
        for item in add_pantry:
            ing_id = (item.get("ingredient_id") or "").strip()
            qty = float(item.get("quantity") or 0)
            if not ing_id or qty <= 0:
                continue
            low_threshold = item.get("low_threshold")
            if low_threshold is not None:
                low_threshold = float(low_threshold)
            kitchen_crud.upsert_pantry_item(
                db, user_id, ing_id, quantity=qty, unit="g", expires_at=None, low_threshold=low_threshold, mode="add",
            )

    malzemeler = recipe.get("malzemeler_json")
    stock_result = check_recipe_stock(
        db, user_id, malzemeler, return_partial_deductions=allow_partial_stock,
    )
    if not allow_partial_stock and not stock_result["ok"]:
        return {
            "success": False,
            "error": "Stok yetersiz (zorunlu malzemeler eksik).",
            "missing": stock_result["missing_ingredients"],
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

    porsiyon = max(1, recipe.get("porsiyon_sayisi") or 1)
    scale = (float(servings_consumed) / porsiyon) if porsiyon else 1.0
    # Enerji: kullanıcıya gösterilen tarif kalorisi ile aynı olsun (toplam_kalori_kcal / porsiyon * yenilen)
    toplam_kalori = recipe.get("toplam_kalori_kcal")
    added_energy_kcal = (float(toplam_kalori) / porsiyon * servings_consumed) if toplam_kalori is not None else 0.0
    # Protein, yağ, karbonhidrat, sodyum: ingredients tablosundan hesaplanan toplam, porsiyon oranına göre
    nutrients = _compute_recipe_nutrients_from_ingredients(db, malzemeler)
    today = date.today()
    totals = _update_daily_totals(
        db,
        user_id,
        today,
        added_energy_kcal=added_energy_kcal,
        added_protein_g=nutrients["protein_g"] * scale,
        added_fat_g=nutrients["total_fat_g"] * scale,
        added_carbohydrate_g=nutrients["carbohydrate_g"] * scale,
        added_sodium_mg=nutrients["sodium_mg"] * scale,
    )

    db.commit()
    return {"success": True, "missing": None, "daily_nutrient_totals": totals}
