"""
Deterministik güvenlik kuralları: alerji, sevilmeyen, ilaç-gıda, hastalık limiti, stok.
LLM asla bu kararları override edemez; sadece backend kuralları uygular.
"""
from __future__ import annotations

import re
from typing import Dict, List, Any, Optional, Tuple

from sqlalchemy import text
from sqlalchemy.orm import Session


# ---------- Ortak normalize + tokenize (stok, alerji, sevilmeyen hepsi aynı) ----------
def normalize(text: str) -> str:
    """Lowercase, trim, noktalama boşluk, ardışık boşlukları tek boşluğa indir."""
    if not text or not isinstance(text, str):
        return ""
    s = str(text).strip().lower()
    s = re.sub(r"[^\w\s]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def tokenize(text: str) -> set[str]:
    """normalize + re.findall(r'\\w+'). Token tabanlı eşleşme için."""
    n = normalize(text)
    return set(re.findall(r"\w+", n))


def _ingredient_tokens_match(tokens_a: set[str], tokens_b: set[str]) -> bool:
    """Token kesişimi boş değilse eşleşme (pantry, alerji, sevilmeyen)."""
    return bool(tokens_a & tokens_b)


def _pantry_name_matches_recipe_ingredient(pantry_name: str, recipe_ingredient_name: str) -> bool:
    """
    Stokta olan besin, tarif içindeki malzeme adıyla makul şekilde eşleşiyorsa True.

    Kurallar:
    - Tam ifade eşleşmesi: normalize(pantry_name) tarif malzemesi içinde alt string olarak geçerse eşleşir
      (\"tavuk\" <-> \"tavuk (bütün)\", \"dana eti\" <-> \"dana eti kuşbaşı\" gibi).
    - Stoktaki isim birden fazla kelimeyse (\"dana eti\", \"süzme yoğurt\" vb.):
      TÜM kelimeler tarif malzemesinin token seti içinde bulunmadıkça eşleşmiş sayılmaz.
      Örn: pantry=\"dana eti\"; tarif=\"dana kıyma\" -> EŞLEŞMEZ (sadece \"dana\" ortak).
    - Tek kelimelik stok isimleri için (\"süt\", \"yumurta\" vb.) önce token kesişimi, sonra hafif substring kontrolü yapılır.
    """
    if not pantry_name or not recipe_ingredient_name:
        return False
    recipe_norm = normalize(recipe_ingredient_name)
    pantry_norm = normalize(pantry_name)
    if not recipe_norm or not pantry_norm:
        return False

    # 1) Tam ifade: normalize(pantry) tarif malzemesinde alt string olarak geçiyorsa
    if len(pantry_norm) >= 2 and pantry_norm in recipe_norm:
        return True
    # veya tarif malzemesi adı stok isminden daha kısa, ama tamamen onun içinde yer alıyorsa
    if len(recipe_norm) >= 2 and recipe_norm in pantry_norm:
        return True

    pantry_tokens = tokenize(pantry_name)
    recipe_tokens = tokenize(recipe_ingredient_name)

    # 2) Çok kelimeli stok isimleri: tüm kelimeler tarif malzemesinin token setinde olmalı
    if len(pantry_tokens) >= 2:
        if pantry_tokens.issubset(recipe_tokens):
            return True
        # Çok kelimeli isimler için sadece tek kelime ortaksa (\"dana\" vs \"dana kıyma\") eşleşme sayma
        return False

    # 3) Tek kelimelik stok isimleri: önce token kesişimi, sonra hafif substring
    if _ingredient_tokens_match(pantry_tokens, recipe_tokens):
        return True
    for p_token in pantry_tokens:
        if p_token and len(p_token) >= 2 and p_token in recipe_norm:
            return True
    return False


def _recipe_ingredient_tokens(malzemeler_json: Any) -> List[set[str]]:
    """malzemeler_json listesinden her Malzeme_Adi için token seti listesi."""
    if not malzemeler_json or not isinstance(malzemeler_json, list):
        return []
    out = []
    for elem in malzemeler_json:
        if not isinstance(elem, dict):
            continue
        name = elem.get("Malzeme_Adi") or elem.get("malzeme_adi")
        if name:
            out.append(tokenize(str(name)))
    return out


# ---------- Alerji: HARD BLOCK ----------
def _recipe_ingredient_names_normalized(malzemeler_json: Any) -> List[str]:
    """Malzemeler_json'dan Malzeme_Adi değerlerinin normalize edilmiş halleri."""
    if not malzemeler_json or not isinstance(malzemeler_json, list):
        return []
    out = []
    for elem in malzemeler_json:
        if not isinstance(elem, dict):
            continue
        name = elem.get("Malzeme_Adi") or elem.get("malzeme_adi")
        if name:
            out.append(normalize(str(name)))
    return out


def has_allergy_match(
    db: Session,
    user_id: Any,
    malzemeler_json: Any,
) -> bool:
    """
    Kullanıcının alerjilerinden biri tarifte varsa True.
    Eşleşme: birebir değil; alerji ifadesi Malzeme_Adi içinde geçiyorsa yeterli (substring + token).
    Örn: alerji "tavuk" -> tarifte "Tavuk (but)" geçiyorsa elenir.
    """
    from app.core.models.user_allergy import UserAllergy

    rows = db.query(UserAllergy).filter(UserAllergy.user_id == user_id).all()
    if not rows:
        return False

    recipe_tokens_list = _recipe_ingredient_tokens(malzemeler_json)
    recipe_ing_norm = _recipe_ingredient_names_normalized(malzemeler_json)

    for row in rows:
        raw = (row.raw_text or "").strip()
        if not raw:
            continue
        norm_allergy = normalize(raw)
        tokens_allergy = tokenize(raw)
        if not norm_allergy and not tokens_allergy:
            continue
        # 1) Token kesişimi (mevcut mantık)
        for ing_tokens in recipe_tokens_list:
            if _ingredient_tokens_match(tokens_allergy, ing_tokens):
                return True
        # 2) Substring: alerji ifadesi herhangi bir malzeme adı içinde geçiyorsa
        if len(norm_allergy) >= 2:
            for ing_norm in recipe_ing_norm:
                if norm_allergy in ing_norm or (len(ing_norm) >= 2 and ing_norm in norm_allergy):
                    return True
    return False


# ---------- Sevilmeyen: SOFT penalty ----------
def disliked_penalty_score(
    db: Session,
    user_id: Any,
    malzemeler_json: Any,
) -> float:
    """Eşleşen sevilmeyen malzeme sayısına göre ceza (örn. 0.2 per match)."""
    from app.core.models.user_disliked_ingredient import UserDislikedIngredient

    rows = db.query(UserDislikedIngredient).filter(
        UserDislikedIngredient.user_id == user_id
    ).all()
    if not rows:
        return 0.0

    recipe_tokens_list = _recipe_ingredient_tokens(malzemeler_json)
    matches = 0
    for row in rows:
        raw = (row.raw_text or row.free_text or "").strip()
        if not raw:
            continue
        tokens_disliked = tokenize(raw)
        if not tokens_disliked:
            continue
        for ing_tokens in recipe_tokens_list:
            if _ingredient_tokens_match(tokens_disliked, ing_tokens):
                matches += 1
                break
    return 0.2 * matches


# ---------- İlaç–gıda: HARD DROP (talimat) ----------
def has_drug_interaction(
    db: Session,
    user_id: Any,
    malzemeler_json: Any,
) -> bool:
    """Kullanıcı ilacı ile tarifte etkileşen besin varsa True (tarif DROP edilmeli)."""
    from app.core.models.user_drug import UserDrug

    drugs = db.query(UserDrug).filter(UserDrug.user_id == user_id).all()
    if not drugs:
        return False

    recipe_tokens_list = _recipe_ingredient_tokens(malzemeler_json)
    for drug in drugs:
        stmt = text("""
            SELECT food_name_tr FROM drug_food_interactions WHERE drug_name = :dn
        """)
        rows = db.execute(stmt, {"dn": drug.drug_name}).fetchall()
        for r in rows:
            food_tr = (r[0] or "").strip().lower()
            if not food_tr:
                continue
            tokens_food = tokenize(food_tr)
            for ing_tokens in recipe_tokens_list:
                if _ingredient_tokens_match(tokens_food, ing_tokens):
                    return True
    return False


def drug_interaction_warnings(
    db: Session,
    user_id: Any,
    malzemeler_json: Any,
) -> List[str]:
    """Kullanıcının ilaçları + drug_food_interactions; tarifte food_name_tr token eşleşirse SOFT WARNING (hard block değil)."""
    from app.core.models.user_drug import UserDrug

    drugs = db.query(UserDrug).filter(UserDrug.user_id == user_id).all()
    if not drugs:
        return []

    recipe_tokens_list = _recipe_ingredient_tokens(malzemeler_json)
    # Tüm tarif malzeme adlarını birleştir (orijinal haliyle kontrol için)
    recipe_ingredient_names = []
    if malzemeler_json and isinstance(malzemeler_json, list):
        for elem in malzemeler_json:
            if isinstance(elem, dict):
                name = elem.get("Malzeme_Adi") or elem.get("malzeme_adi")
                if name:
                    recipe_ingredient_names.append(str(name).lower())

    warnings = []
    for drug in drugs:
        stmt = text("""
            SELECT food_name_tr, recommendation_tr, interaction_effect
            FROM drug_food_interactions
            WHERE drug_name = :dn
        """)
        rows = db.execute(stmt, {"dn": drug.drug_name}).fetchall()
        for r in rows:
            food_tr = (r[0] or "").strip().lower()
            if not food_tr:
                continue
            tokens_food = tokenize(food_tr)
            for ing_tokens in recipe_tokens_list:
                if _ingredient_tokens_match(tokens_food, ing_tokens):
                    rec = (r[1] or "").strip() or (r[2] or "").strip()
                    msg = f"İlaç–gıda: {drug.drug_name} – {food_tr}. {rec}" if rec else f"İlaç–gıda: {drug.drug_name} – {food_tr}."
                    warnings.append(msg)
                    break
    return warnings


# ---------- Hastalık besin limiti: HARD DROP (talimat) ----------
def would_exceed_disease_limit(
    db: Session,
    user_id: Any,
    recipe_calories_per_serving: Optional[float],
    recipe_servings: Optional[int],
    daily_totals: Optional[Dict[str, Any]],
) -> bool:
    """Bu tarifin bir porsiyonu eklenince günlük limit aşılıyorsa True (tarif DROP)."""
    from app.core.models.user_disease import UserDisease
    from app.core.models.disease_nutrient_limit import DiseaseNutrientLimit

    diseases = db.query(UserDisease).filter(UserDisease.user_id == user_id).all()
    if not diseases:
        return False

    for d in diseases:
        limits = db.query(DiseaseNutrientLimit).filter(
            DiseaseNutrientLimit.disease_name == d.disease_name
        ).all()
        for lim in limits:
            if (lim.nutrient_tag or "").lower() != "energy_kcal":
                continue
            current = 0.0
            if daily_totals and daily_totals.get("total_energy_kcal") is not None:
                current = float(daily_totals["total_energy_kcal"])
            add = float(recipe_calories_per_serving or 0)
            total_after = current + add
            if lim.value is not None and total_after > float(lim.value):
                return True
    return False


# ---------- Hastalık besin limiti (kalori ile başla) — uyarı metni (polish için) ----------
def disease_limit_warnings(
    db: Session,
    user_id: Any,
    recipe_calories_per_serving: Optional[float],
    recipe_servings: Optional[int],
    daily_totals: Optional[Dict[str, Any]],
) -> List[str]:
    """user_diseases + disease_nutrient_limits + daily_nutrient_totals; limit aşılıyorsa uyarı."""
    from app.core.models.user_disease import UserDisease
    from app.core.models.disease_nutrient_limit import DiseaseNutrientLimit

    diseases = db.query(UserDisease).filter(UserDisease.user_id == user_id).all()
    if not diseases:
        return []

    warnings = []
    for d in diseases:
        limits = db.query(DiseaseNutrientLimit).filter(
            DiseaseNutrientLimit.disease_name == d.disease_name
        ).all()
        for lim in limits:
            if (lim.nutrient_tag or "").lower() != "energy_kcal":
                continue
            # Günlük toplam + bu tarifin bir porsiyonu
            current = 0.0
            if daily_totals and daily_totals.get("total_energy_kcal") is not None:
                current = float(daily_totals["total_energy_kcal"])
            add = float(recipe_calories_per_serving or 0)
            total_after = current + add
            lim_val = lim.value
            if lim_val is not None and total_after > float(lim_val):
                warnings.append(
                    "Bu değer DSÖ limitini aşabilir. Bu tıbbi tavsiye değildir, bilgilendirme amaçlıdır."
                )
                break
    return warnings


# ---------- Staple malzemeler: sadece tuz, karabiber, pul biber vb. temel baharatlar ----------
# Soğan, sarımsak, domates, salça, limon, sirke, tarhun, zencefil vb. burada yok; stokta yoksa eksik sayılır.
STAPLE_NAME_TOKENS = frozenset({
    "su", "water", "tuz", "salt", "yağ", "yag", "oil", "zeytinyağ", "ayçiçek",
    "karabiber", "pepper", "pulbiber", "kırmızı", "şeker", "seker", "sugar",
    "toz", "vanilya", "vanilla", "tarçın", "tarcin", "karbonat", "kabartma",
    "baharat", "spice", "spices",
})
# Bu malzemeler asla staple sayılmaz; tarifte varsa stokta da olmalı
NEVER_STAPLE_TOKENS = frozenset({
    "tarhun", "taragon", "zencefil", "ginger", "soğan", "sogan", "sarımsak", "sarimsak",
    "domates", "salça", "salca", "limon", "lemon", "sirke", "vinegar",
    "kimyon", "kekik", "nane", "fesleğen", "feslegen", "biberiye", "çeşni", "cesni", "aromatik",
    "biber",  # taze biber / kapya; karabiber/pulbiber staple'da kalır
})
STAPLE_THRESHOLD_G = 10.0
STAPLE_THRESHOLD_ML = 15.0


def _is_staple(elem: Dict[str, Any]) -> bool:
    """
    Staple sayılır: (a) adında staples listesinden bir token var
    veya (b) Standart_Miktar eşik altı: g<10 veya ml<15.
    NEVER_STAPLE_TOKENS içindekiler (tarhun vb.) her zaman zorunlu sayılır.
    """
    if not isinstance(elem, dict):
        return True
    name = elem.get("Malzeme_Adi") or elem.get("malzeme_adi")
    tokens = tokenize(str(name or ""))
    if tokens & NEVER_STAPLE_TOKENS:
        return False
    if tokens & STAPLE_NAME_TOKENS:
        return True
    try:
        miktar = float(elem.get("Standart_Miktar") or 0)
    except (TypeError, ValueError):
        return False
    birim = (elem.get("Birim") or "").strip().lower()
    if birim in ("g", "gr", "gram"):
        return miktar < STAPLE_THRESHOLD_G
    if birim in ("ml", "ml.", "mililitre"):
        return miktar < STAPLE_THRESHOLD_ML
    return False


# ---------- Stok: SADECE pantry_items.ingredient_id (ingredients tablosu YOK) ----------
def check_recipe_stock(
    db: Session,
    user_id: Any,
    malzemeler_json: Any,
    return_partial_deductions: bool = False,
) -> Dict[str, Any]:
    """
    Pantry–tarif eşleşmesi: token kesişimi.
    pantry_name = pantry_items.ingredient_id (string); ingredients tablosu kullanılmaz.
    match <=> tokens(pantry_name) ∩ tokens(recipe Malzeme_Adi) != ∅.
    return_partial_deductions=True ise: stokta ne varsa o kadar düşülecek (min(qty, need)).
    """
    empty_result = {
        "ok": True,
        "missing": [],
        "deductions": [],
        "stock_match_score": 0.0,
        "missing_ingredients": [],
        "available_ingredients": [],
        "non_staple_total": 0.0,
        "non_staple_available": 0.0,
    }
    if not malzemeler_json or not isinstance(malzemeler_json, list):
        return empty_result

    from app.core.models.pantry_items import PantryItem

    # Sadece pantry_items; ingredient_id = malzeme adı (string)
    pantry_rows = (
        db.query(PantryItem)
        .filter(PantryItem.user_id == user_id)
        .all()
    )
    pantry_list = [(p, str((p.ingredient_id or "")).strip()) for p in pantry_rows]

    missing_non_staple = []
    deductions = []
    missing_display = []
    available_display = []
    non_staple_total = 0.0
    non_staple_available = 0.0

    # Tarif malzemesi -> (need_val, staple, recipe_tokens) ve token ile eşleşen pantry
    recipe_items: List[Tuple[str, float, bool, set[str], Optional[str], Optional[float]]] = []
    for elem in malzemeler_json:
        if not isinstance(elem, dict):
            continue
        name = elem.get("Malzeme_Adi") or elem.get("malzeme_adi")
        need = elem.get("Standart_Miktar")
        if name is None or need is None:
            continue
        try:
            need_val = float(need)
        except (TypeError, ValueError):
            continue
        if need_val <= 0:
            continue
        name_str = str(name).strip()
        staple = _is_staple(elem)
        recipe_tokens = tokenize(name_str)
        matched_ing_id = None
        matched_qty = None
        # Aynı tarif malzemesine birden fazla stok eşleşebilir (örn. "Tavuk" ve "Tavuk But (Kemiksiz)").
        # En yüksek miktara sahip eşleşmeyi seç ki kullanıcının dolu stoku kullanılsın.
        for pantry_item, ing_name in pantry_list:
            if _pantry_name_matches_recipe_ingredient(ing_name, name_str):
                qty = float(pantry_item.quantity or 0)
                if matched_qty is None or qty > matched_qty:
                    matched_ing_id = pantry_item.ingredient_id
                    matched_qty = qty
        recipe_items.append((name_str, need_val, staple, recipe_tokens, matched_ing_id, matched_qty))

    # Aynı pantry’ye bağlanan tarif kalemlerini topla (örn. Brokoli + Haşlanmış Brokoli -> aynı ingredient_id)
    need_per_ingredient: Dict[str, float] = {}
    non_staple_need_per_ingredient: Dict[str, float] = {}
    names_per_ingredient: Dict[str, List[Tuple[str, float, bool]]] = {}
    for name_str, need_val, staple, _rt, ing_id, qty in recipe_items:
        if ing_id is None:
            if not staple:
                missing_non_staple.append(f"{name_str}: stokta eşleşen malzeme yok")
                missing_display.append(name_str)
                non_staple_total += need_val
            continue
        need_per_ingredient[ing_id] = need_per_ingredient.get(ing_id, 0) + need_val
        if not staple:
            non_staple_need_per_ingredient[ing_id] = non_staple_need_per_ingredient.get(ing_id, 0) + need_val
            non_staple_total += need_val
        names_per_ingredient.setdefault(ing_id, []).append((name_str, need_val, staple))

    for pantry_item, _ in pantry_list:
        ing_id = pantry_item.ingredient_id
        total_need = need_per_ingredient.get(ing_id, 0)
        if total_need <= 0:
            continue
        qty = float(pantry_item.quantity or 0)
        non_staple_need = non_staple_need_per_ingredient.get(ing_id, 0)
        deduct_qty = min(qty, total_need) if return_partial_deductions else (total_need if qty >= total_need else 0)
        if deduct_qty > 0:
            deductions.append({"ingredient_id": ing_id, "quantity": deduct_qty})
        if qty >= total_need:
            non_staple_available += non_staple_need
            for name_str, _nv, staple in names_per_ingredient.get(ing_id, []):
                if not staple:
                    available_display.append(name_str)
        else:
            for name_str, _nv, staple in names_per_ingredient.get(ing_id, []):
                if not staple:
                    missing_non_staple.append(f"{name_str}: gerekli {total_need}, mevcut {qty}")
                    missing_display.append(name_str)
            if non_staple_need > 0:
                non_staple_available += min(qty, total_need) * (non_staple_need / total_need)

    if non_staple_total <= 0:
        stock_match_score = 0.0
        missing_display = []
        available_display = []
    else:
        stock_match_score = non_staple_available / non_staple_total

    return {
        "ok": len(missing_non_staple) == 0,
        "missing": missing_non_staple,
        "deductions": deductions,
        "stock_match_score": round(stock_match_score, 4),
        "missing_ingredients": missing_display,
        "available_ingredients": available_display,
        "non_staple_total": round(non_staple_total, 2),
        "non_staple_available": round(non_staple_available, 2),
    }
