"""
Tarif sohbet öneri akışı: session/message, retrieval, rules, sıralama, yanıt.
"""
from __future__ import annotations

import logging
import uuid
from datetime import date
from typing import List, Dict, Any, Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.models.chat_session import ChatSession
from app.core.models.chat_message import ChatMessage
from app.core.models.rag_retrieval_log import RagRetrievalLog
from app.core.models.recipe_suggestion_log import RecipeSuggestionLog

from app.core.services.retrieval_service import retrieve_recipe_ids
from app.core.services.embedding_service import embed_query
from app.core.services.rules_engine import (
    has_allergy_match,
    has_drug_interaction,
    would_exceed_disease_limit,
    disliked_penalty_score,
    drug_interaction_warnings,
    disease_limit_warnings,
    check_recipe_stock,
    tokenize,
    STAPLE_NAME_TOKENS,
)
from app.core.config import (
    DEBUG_RECIPE_SCORING,
    DEBUG_LLM_SOURCES,
    USE_RECIPE_LLM,
    OPENAI_API_KEY,
    RAG_CANDIDATE_K,
    LLM_RERANK_K,
    CHAT_HISTORY_N,
)
from app.core.services.intent_service import extract_intent, IntentResult
from app.core.services.llm_service import generate_assistant_response, generate_general_chat_response
from app.core.services.llm_rerank_service import rerank_recipe_ids as llm_rerank

logger = logging.getLogger(__name__)

TOP_K_PANTRY = 80
MAX_PANTRY_QUERY_ITEMS = 6
LAST_SUGGESTED_LIMIT = 30
TOP_LLM_CANDIDATES = 15  # polish için LLM'e verilen aday sayısı
CARDS_PER_RESPONSE = 3  # Her yanıtta 3 tarif kartı (mod seçimine göre stok öncelikli veya değil)
# Mode ağırlıkları: COOK_NOW stok ağırlıklı, DISCOVER rag ağırlıklı
WEIGHT_COOK_NOW_STOCK = 0.55
WEIGHT_COOK_NOW_RAG = 0.35
WEIGHT_COOK_NOW_LLM = 0.10
# Discover = stok OLMADAN: stok ağırlığı 0, sadece RAG + LLM sırası
WEIGHT_DISCOVER_RAG = 0.85
WEIGHT_DISCOVER_STOCK = 0.0
WEIGHT_DISCOVER_LLM = 0.15


def _get_pantry_query_text(db: Session, user_id: uuid.UUID, max_items: int = MAX_PANTRY_QUERY_ITEMS) -> str:
    from app.core.models.pantry_items import PantryItem
    rows = db.query(PantryItem).filter(PantryItem.user_id == user_id).all()
    non_staple = []
    for p in rows:
        name = (p.ingredient_id or "").strip()
        if not name:
            continue
        if tokenize(name) & STAPLE_NAME_TOKENS:
            continue
        non_staple.append(name.lower())
        if len(non_staple) >= max_items:
            break
    return " ".join(non_staple) if non_staple else ""


def _get_user_context(db: Session, user_id: uuid.UUID, pantry_query: str) -> Dict[str, Any]:
    from app.core.crud import allergies as crud_allergies
    from app.core.crud import disliked as crud_disliked
    from app.core.crud import diseases as crud_diseases
    from app.core.crud import drugs as crud_drugs

    allergies = [a.get("display_name") or a.get("raw_text") or "" for a in crud_allergies.list_allergies(db, user_id)]
    disliked = [d.get("display_name") or "" for d in crud_disliked.list_disliked(db, user_id)]
    diseases = [d.disease_name for d in crud_diseases.list_diseases(db, user_id)]
    drugs = [d.drug_name for d in crud_drugs.list_user_drugs(db, user_id)]

    return {
        "allergies": [a for a in allergies if a],
        "disliked": [d for d in disliked if d],
        "diseases": diseases,
        "drugs": drugs,
        "pantry_summary": pantry_query if pantry_query else "Belirtilmemiş",
    }


def _get_last_n_messages(db: Session, session_id: uuid.UUID, n: int = CHAT_HISTORY_N) -> List[Dict[str, str]]:
    rows = (
        db.query(ChatMessage)
        .filter(ChatMessage.session_id == session_id)
        .order_by(ChatMessage.created_at.desc())
        .limit(n)
        .all()
    )
    return [{"role": r.role or "user", "content": r.content or ""} for r in reversed(rows)]


def get_or_create_session(db: Session, user_id: uuid.UUID, session_id: Optional[uuid.UUID] = None) -> uuid.UUID:
    if session_id:
        s = db.query(ChatSession).filter(ChatSession.session_id == session_id, ChatSession.user_id == user_id).first()
        if s:
            return s.session_id
    new_id = session_id or uuid.uuid4()
    db.add(ChatSession(session_id=new_id, user_id=user_id))
    db.commit()
    return new_id


def _fetch_recipes_by_ids(db: Session, tarif_ids: List[str]) -> List[Dict[str, Any]]:
    if not tarif_ids:
        return []
    placeholders = ", ".join(f":id_{i}" for i in range(len(tarif_ids)))
    params = {f"id_{i}": tid for i, tid in enumerate(tarif_ids)}
    sql = text(f"""
        SELECT tarif_id, tarif_adi, kategori, porsiyon_sayisi, toplam_kalori_kcal,
               kaynak_url, fotograf_url, malzemeler_json
        FROM recipes
        WHERE tarif_id IN ({placeholders})
    """)
    rows = db.execute(sql, params).fetchall()
    return [{
        "tarif_id": r[0],
        "tarif_adi": r[1],
        "kategori": r[2],
        "porsiyon_sayisi": r[3],
        "toplam_kalori_kcal": r[4],
        "kaynak_url": r[5],
        "fotograf_url": r[6],
        "malzemeler_json": r[7],
    } for r in rows]


def _get_daily_totals(db: Session, user_id: uuid.UUID, day: date) -> Optional[Dict[str, Any]]:
    from app.core.models.daily_nutrient_total import DailyNutrientTotal
    row = db.query(DailyNutrientTotal).filter(DailyNutrientTotal.user_id == user_id, DailyNutrientTotal.day == day).first()
    if not row:
        return None
    return {
        "total_energy_kcal": float(row.total_energy_kcal) if row.total_energy_kcal is not None else None,
        "total_protein_g": float(row.total_protein_g) if row.total_protein_g is not None else None,
        "total_fat_g": float(row.total_fat_g) if row.total_fat_g is not None else None,
        "total_carbohydrate_g": float(row.total_carbohydrate_g) if row.total_carbohydrate_g is not None else None,
        "total_sodium_mg": float(row.total_sodium_mg) if row.total_sodium_mg is not None else None,
    }


def _get_last_suggested_recipe_ids(db: Session, session_id: uuid.UUID, limit: int = LAST_SUGGESTED_LIMIT) -> List[str]:
    try:
        rows = (
            db.query(RecipeSuggestionLog.recipe_id)
            .filter(RecipeSuggestionLog.session_id == session_id)
            .order_by(RecipeSuggestionLog.created_at.desc())
            .limit(limit)
            .all()
        )
        return [str(r[0]) for r in rows if r and r[0]]
    except Exception:
        db.rollback()
        return []


def _log_suggested_recipes(db: Session, session_id: uuid.UUID, recipe_ids: List[str]) -> None:
    if not recipe_ids:
        return
    try:
        for rid in recipe_ids[:25]:
            db.add(RecipeSuggestionLog(session_id=session_id, recipe_id=str(rid)))
        db.commit()
    except Exception:
        db.rollback()


def _dish_type_to_category_filters(dish_type: str, intent_result: Optional[IntentResult] = None) -> Dict[str, Any]:
    """
    rag_documents.metadata->kategori filtresi: dish_type + intent include/exclude_categories birleşik.
    """
    dt = (dish_type or "any").lower().strip()
    inc, exc = [], []
    if dt == "soup":
        inc = ["çorba"]
    elif dt == "dessert":
        inc = ["tatlı", "tatli"]
    elif dt == "breakfast":
        inc = ["kahvaltı", "kahvalti", "sabah"]
    elif dt == "salad":
        inc = ["salata"]
    elif dt == "meze":
        inc = ["meze", "atıştırmalık", "atistirmalik", "başlangıç", "baslangic", "aperatif"]
    if intent_result:
        inc = list(dict.fromkeys(inc + [c for c in (intent_result.include_categories or []) if c]))
        exc = list(dict.fromkeys([c for c in (intent_result.exclude_categories or []) if c]))
    return {"include_categories": inc, "exclude_categories": exc}


def _recipe_matches_dish_type(recipe: Dict[str, Any], dish_type: str) -> bool:
    """
    dish_type dessert/soup/meze/breakfast/salad ise tarifin kategori alanı o türe uymalı.
    any ise her zaman True. Uymazsa False (tarif DROP edilmeli).
    """
    dt = (dish_type or "any").lower().strip()
    if dt == "any" or not dt:
        return True
    cat = (recipe.get("kategori") or "").lower()
    if dt == "dessert":
        return "tatlı" in cat or "tatli" in cat
    if dt == "soup":
        return "çorba" in cat or "corba" in cat
    if dt == "breakfast":
        return "kahvalt" in cat or "sabah" in cat
    if dt == "meze":
        return any(x in cat for x in ("meze", "atıştır", "atistirmalik", "salata", "aperatif", "başlang", "baslangic"))
    if dt == "salad":
        return "salata" in cat
    return True


def _category_alignment_score(dish_type: str, kategori: str) -> float:
    cat = (kategori or "").lower()
    dt = (dish_type or "any").lower()
    if dt == "dessert":
        return 1.0 if ("tatlı" in cat or "tatli" in cat) else 0.05
    if dt == "soup":
        return 1.0 if ("çorba" in cat or "corba" in cat) else 0.2
    if dt == "breakfast":
        return 1.0 if ("kahvalt" in cat or "sabah" in cat) else 0.4
    if dt == "meze":
        return 1.0 if ("meze" in cat or "atıştır" in cat or "salata" in cat or "aperatif" in cat or "başlang" in cat) else 0.3
    if dt == "salad":
        return 1.0 if "salata" in cat else 0.3
    return 1.0


def _recipe_contains_any_ingredient(recipe: Dict[str, Any], include_ings: List[str]) -> bool:
    if not include_ings:
        return True
    malzemeler = recipe.get("malzemeler_json") or []
    if not isinstance(malzemeler, list):
        return False
    ing_text = " ".join(str(m.get("Malzeme_Adi") or m.get("malzeme_adi") or "").lower() for m in malzemeler if isinstance(m, dict))
    title_cat = ((recipe.get("tarif_adi") or "") + " " + (recipe.get("kategori") or "")).lower()
    combined = title_cat + " " + ing_text
    for ing in include_ings:
        s = (ing or "").strip().lower()
        if s and s in combined:
            return True
    return False


def _recipe_contains_exclude_ingredient(recipe: Dict[str, Any], exclude_ings: List[str]) -> bool:
    """Tarif exclude listesinden bir malzeme içeriyorsa True (DROP)."""
    if not exclude_ings:
        return False
    malzemeler = recipe.get("malzemeler_json") or []
    if not isinstance(malzemeler, list):
        return False
    ing_text = " ".join(str(m.get("Malzeme_Adi") or m.get("malzeme_adi") or "").lower() for m in malzemeler if isinstance(m, dict))
    title_cat = ((recipe.get("tarif_adi") or "") + " " + (recipe.get("kategori") or "")).lower()
    combined = title_cat + " " + ing_text
    for ing in exclude_ings:
        s = (ing or "").strip().lower()
        if s and s in combined:
            return True
    return False


def _short_ingredients(malzemeler_json: Any, max_n: int = 10) -> List[str]:
    """Rerank için kısa malzeme listesi (token tasarrufu)."""
    if not malzemeler_json or not isinstance(malzemeler_json, list):
        return []
    out = []
    for elem in malzemeler_json[:max_n]:
        if isinstance(elem, dict):
            name = elem.get("Malzeme_Adi") or elem.get("malzeme_adi")
            if name:
                out.append(str(name).strip()[:40])
    return out[:max_n]


def suggest_recipes(
    db: Session,
    user_id: uuid.UUID,
    message: str,
    session_id: Optional[uuid.UUID] = None,
    mode: Optional[str] = None,
    query_embedding: Optional[List[float]] = None,
) -> Dict[str, Any]:
    session_uuid = get_or_create_session(db, user_id, session_id)

    # save user msg
    user_msg_id = uuid.uuid4()
    db.add(ChatMessage(message_id=user_msg_id, session_id=session_uuid, role="user", content=message or ""))
    db.commit()

    chat_history = _get_last_n_messages(db, session_uuid, CHAT_HISTORY_N)
    last_cards = _get_last_suggested_recipe_ids(db, session_uuid, 10)

    intent_result, intent_from_llm = extract_intent(message or "", chat_history=chat_history, last_cards=last_cards)

    # --- general chat ---
    if (intent_result.intent or "").strip().lower() == "general_chat":
        assistant_text = None
        general_chat_from_llm = False
        if USE_RECIPE_LLM and OPENAI_API_KEY:
            assistant_text = generate_general_chat_response(message or "", chat_history=chat_history)
            general_chat_from_llm = bool(assistant_text and assistant_text.strip())
        if not assistant_text:
            assistant_text = "Merhaba!"
            logger.info("LLM general_chat: fallback (cevap yok veya LLM kapalı)")
        else:
            logger.info("LLM general_chat: %s", "llm" if general_chat_from_llm else "fallback")
        db.add(ChatMessage(message_id=uuid.uuid4(), session_id=session_uuid, role="assistant", content=assistant_text))
        db.commit()
        out = {"session_id": str(session_uuid), "assistant_text": assistant_text, "cards": []}
        if DEBUG_LLM_SOURCES:
            out["llm_sources"] = {"intent": intent_from_llm, "general_chat": general_chat_from_llm, "rerank": False, "polish": False}
        return out

    # --- recipe request (talimat: tek retrieval 300, hard drop, llm rerank 40, mode score, top 5) ---
    base_q = (intent_result.rewrite_query or message or "").strip()
    inc_ings = [x.strip() for x in (intent_result.include_ingredients or []) if isinstance(x, str) and x.strip()]
    exc_ings = [x.strip() for x in (intent_result.exclude_ingredients or []) if isinstance(x, str) and x.strip()]
    if inc_ings:
        base_q = (base_q + " " + " ".join(inc_ings)).strip()
    dish_hint = intent_result.dish_type or "any"
    # Mod: API'den gelen (chat ekranına girmeden seçilen) öncelikli; yoksa intent
    resolved_mode = (mode or intent_result.mode or "discover").strip().lower()
    if resolved_mode not in ("cook_now", "discover"):
        resolved_mode = "discover"
    mode = resolved_mode

    filters = _dish_type_to_category_filters(dish_hint, intent_result)
    if query_embedding is None:
        query_embedding = embed_query(base_q)

    # RAG: mesaj (rewrite_query) embed edilip rag_documents tablosunda vector aranıyor
    retrieved = retrieve_recipe_ids(db, base_q, top_k=RAG_CANDIDATE_K, query_embedding=query_embedding, filters=filters)
    rag_sources = [{"recipe_id": rid, "score": sc} for rid, sc in retrieved]
    candidate_scores: Dict[str, float] = {rid: float(sc) for rid, sc in retrieved}
    logger.info(
        "RAG retrieval: rag_documents tablosundan base_q=%r ile %d aday çekildi (vector=%s)",
        base_q[:80] if base_q else "",
        len(retrieved),
        "evet" if query_embedding else "hayır (ILIKE fallback)",
    )

    db.add(RagRetrievalLog(
        retrieval_id=uuid.uuid4(),
        message_id=user_msg_id,
        query_text=message or "",
        retrieved_sources=rag_sources[:100],
        top_k=RAG_CANDIDATE_K,
    ))
    db.commit()

    all_candidate_ids = list(candidate_scores.keys())
    recipes = _fetch_recipes_by_ids(db, all_candidate_ids)
    recipe_map = {r["tarif_id"]: r for r in recipes}
    today_totals = _get_daily_totals(db, user_id, date.today())
    pantry_query = _get_pantry_query_text(db, user_id, MAX_PANTRY_QUERY_ITEMS)

    # HARD filters: allergy, drug, disease, include_ingredients, exclude_ingredients, exclude_categories, dish_type
    filtered: List[str] = []
    for rid in all_candidate_ids:
        rec = recipe_map.get(rid)
        if not rec:
            continue
        if has_allergy_match(db, user_id, rec.get("malzemeler_json")):
            continue
        if has_drug_interaction(db, user_id, rec.get("malzemeler_json")):
            continue
        porsiyon = rec.get("porsiyon_sayisi") or 1
        cal_total = rec.get("toplam_kalori_kcal")
        cal_per = float(cal_total) / porsiyon if cal_total is not None and porsiyon else None
        if would_exceed_disease_limit(db, user_id, cal_per, porsiyon, today_totals):
            continue
        if not _recipe_contains_any_ingredient(rec, inc_ings):
            continue
        if _recipe_contains_exclude_ingredient(rec, exc_ings):
            continue
        cat = (rec.get("kategori") or "").lower()
        if any((c or "").lower() in cat for c in (intent_result.exclude_categories or [])):
            continue
        # dish_type: tatlı istendiğinde ana yemek/çorba DROP; çorba/meze vb. aynı mantık
        if not _recipe_matches_dish_type(rec, dish_hint):
            continue
        filtered.append(rid)

    if intent_result.wants_alternatives:
        seen = set(_get_last_suggested_recipe_ids(db, session_uuid, LAST_SUGGESTED_LIMIT))
        filtered = [rid for rid in filtered if rid not in seen]

    # Rerank candidates: short form for LLM (recipe_id, title, category, short_ingredients, rag_score, stock_match_score)
    candidates_rerank: List[Dict[str, Any]] = []
    for rid in filtered:
        rec = recipe_map.get(rid)
        if not rec:
            continue
        stock_result = check_recipe_stock(db, user_id, rec.get("malzemeler_json"))
        rag_sc = candidate_scores.get(rid, 0.0)
        candidates_rerank.append({
            "recipe_id": rid,
            "title": (rec.get("tarif_adi") or "").strip(),
            "category": (rec.get("kategori") or "").strip(),
            "short_ingredients": _short_ingredients(rec.get("malzemeler_json")),
            "rag_score": round(rag_sc, 3),
            "stock_match_score": round(stock_result["stock_match_score"], 3),
        })

    avoid_ids: List[str] = []
    if intent_result.wants_alternatives:
        avoid_ids = _get_last_suggested_recipe_ids(db, session_uuid, LAST_SUGGESTED_LIMIT)

    context = _get_user_context(db, user_id, pantry_query)
    intent_payload = intent_result.model_dump()
    intent_payload["mode"] = mode
    stock_summary_llm = {"pantry_summary": context.get("pantry_summary") or "", "top_items": (pantry_query or "").split()[:15]}

    rerank_result = llm_rerank(
        user_message=message or "",
        intent=intent_payload,
        user_context={"allergies": context.get("allergies"), "disliked": context.get("disliked"), "diseases": context.get("diseases"), "drugs": context.get("drugs")},
        stock_summary=stock_summary_llm,
        candidates=candidates_rerank,
        avoid_ids=avoid_ids,
        top_m=LLM_RERANK_K,
    )
    rerank_from_llm = bool(rerank_result and rerank_result.get("selected_recipe_ids"))
    logger.info("LLM rerank: %s", "llm" if rerank_from_llm else "fallback (yok veya boş)")
    selected_recipe_ids: List[str] = []
    if rerank_result and rerank_result.get("selected_recipe_ids"):
        selected_recipe_ids = [str(x) for x in rerank_result["selected_recipe_ids"] if x][:LLM_RERANK_K]
    if not selected_recipe_ids:
        selected_recipe_ids = filtered[:LLM_RERANK_K]

    # Final score (mode): COOK_NOW 0.55*stock + 0.35*rag + 0.10*llm_bonus - disliked; DISCOVER 0.70*rag + 0.15*stock + 0.15*llm_bonus - disliked
    llm_rank_index = {rid: i for i, rid in enumerate(selected_recipe_ids)}
    scored = []
    for rid in selected_recipe_ids:
        rec = recipe_map.get(rid)
        if not rec:
            continue
        rag_sc = candidate_scores.get(rid, 0.0)
        stock_result = check_recipe_stock(db, user_id, rec.get("malzemeler_json"))
        disliked = disliked_penalty_score(db, user_id, rec.get("malzemeler_json"))
        idx = llm_rank_index.get(rid, 99)
        llm_bonus = max(0.0, 1.0 - (idx / max(LLM_RERANK_K, 1)))

        if mode == "cook_now":
            final_score = (
                WEIGHT_COOK_NOW_STOCK * stock_result["stock_match_score"] +
                WEIGHT_COOK_NOW_RAG * rag_sc +
                WEIGHT_COOK_NOW_LLM * llm_bonus -
                disliked
            )
        else:
            final_score = (
                WEIGHT_DISCOVER_RAG * rag_sc +
                WEIGHT_DISCOVER_STOCK * stock_result["stock_match_score"] +
                WEIGHT_DISCOVER_LLM * llm_bonus -
                disliked
            )

        porsiyon = rec.get("porsiyon_sayisi") or 1
        cal_total = rec.get("toplam_kalori_kcal")
        cal_per = float(cal_total) / porsiyon if cal_total is not None and porsiyon else None
        warnings: List[str] = []
        warnings.extend(drug_interaction_warnings(db, user_id, rec.get("malzemeler_json")))
        warnings.extend(disease_limit_warnings(db, user_id, cal_per, porsiyon, today_totals))
        if disliked > 0:
            warnings.append("Bu tarif sevmediğiniz bir malzeme içeriyor.")
        if not stock_result["ok"] and stock_result.get("missing"):
            warnings.append("Stok: " + "; ".join((stock_result["missing"] or [])[:3]))

        scored.append({
            "tarif_id": rid,
            "score": final_score,
            "warnings": warnings,
            "missing_ingredients": stock_result.get("missing_ingredients") or [],
            "available_ingredients": stock_result.get("available_ingredients") or [],
            "stock_match_score": stock_result["stock_match_score"],
            "debug_msg_score": rag_sc if DEBUG_RECIPE_SCORING else None,
            "debug_final_score": final_score if DEBUG_RECIPE_SCORING else None,
        })

    scored.sort(key=lambda x: -x["score"])
    top = scored[:CARDS_PER_RESPONSE]

    cards: List[Dict[str, Any]] = []
    for i, item in enumerate(top, 1):
        rec = recipe_map.get(item["tarif_id"])
        if not rec:
            continue
        card = {
            "recipe_id": rec["tarif_id"],
            "title": rec.get("tarif_adi") or "",
            "image_url": rec.get("fotograf_url"),
            "reason": "—",  # polisher dolduracak
            "warnings": item["warnings"],
            "badges": [b for b in [rec.get("kategori")] if b],
            "missing_ingredients": item.get("missing_ingredients") or [],
            "available_ingredients": item.get("available_ingredients") or [],
        }
        if DEBUG_RECIPE_SCORING:
            card["debug_msg_score"] = item.get("debug_msg_score")
            card["debug_pantry_score"] = item.get("debug_pantry_score")
            card["debug_final_score"] = item.get("debug_final_score")
        cards.append(card)

    NO_RECIPE_MESSAGE = "Veritabanımızda bu isteğe uygun tarif bulunmamaktadır. Bizi uyardığınız için teşekkürler."
    assistant_text = NO_RECIPE_MESSAGE if not cards else "—"
    polish_from_llm = False

    # LLM Polisher: daha fazla aday ver (TOP_LLM_CANDIDATES), LLM uygun olanları bağlamda görsün; reason sadece gösterilen kartlar için
    if cards and USE_RECIPE_LLM and OPENAI_API_KEY:
        context = _get_user_context(db, user_id, pantry_query)
        user_context_llm = {
            "diseases": context.get("diseases") or [],
            "drugs": context.get("drugs") or [],
            "allergies": context.get("allergies") or [],
            "disliked": context.get("disliked") or [],
        }
        top_for_llm = scored[:TOP_LLM_CANDIDATES]
        stock_summary_llm = {"available_key_ingredients": [], "missing_key_ingredients": []}
        candidates_llm = []
        for idx, item in enumerate(top_for_llm, 1):
            rec = recipe_map.get(item["tarif_id"])
            if not rec:
                continue
            candidates_llm.append({
                "recipe_id": rec["tarif_id"],
                "title": rec.get("tarif_adi") or "",
                "category": (rec.get("kategori") or ""),
                "badges": [b for b in [rec.get("kategori")] if b],
                "warnings": item.get("warnings") or [],
                "rank": idx,
                "stock": {
                    "available": item.get("available_ingredients") or [],
                    "missing": item.get("missing_ingredients") or [],
                }
            })
            stock_summary_llm["available_key_ingredients"].extend(item.get("available_ingredients") or [])
            stock_summary_llm["missing_key_ingredients"].extend(item.get("missing_ingredients") or [])
        stock_summary_llm["available_key_ingredients"] = list(dict.fromkeys(stock_summary_llm["available_key_ingredients"]))[:15]
        stock_summary_llm["missing_key_ingredients"] = list(dict.fromkeys(stock_summary_llm["missing_key_ingredients"]))[:15]

        cards_to_show_recipe_ids = [c["recipe_id"] for c in cards if c.get("recipe_id")]

        intent_payload = intent_result.model_dump()

        llm_out = generate_assistant_response(
            user_message=message or "",
            intent=intent_payload,
            user_context=user_context_llm,
            stock_summary=stock_summary_llm,
            candidates=candidates_llm,
            cards_to_show_recipe_ids=cards_to_show_recipe_ids,
            chat_history=chat_history,
        )

        if llm_out:
            if isinstance(llm_out.get("assistant_text"), str) and llm_out["assistant_text"].strip():
                assistant_text = llm_out["assistant_text"].strip()
                polish_from_llm = True

            reasons_by_id = {r.get("recipe_id"): r.get("reason") for r in (llm_out.get("card_reasons") or []) if isinstance(r, dict)}
            warnings_by_id = {w.get("recipe_id"): w.get("warnings") for w in (llm_out.get("warnings_rewritten") or []) if isinstance(w, dict)}

            for c in cards:
                rid = c.get("recipe_id")
                if rid and reasons_by_id.get(rid):
                    c["reason"] = reasons_by_id[rid]
                if rid and isinstance(warnings_by_id.get(rid), list) and warnings_by_id[rid]:
                    c["warnings"] = warnings_by_id[rid]

    logger.info("LLM polish: %s", "llm" if polish_from_llm else "fallback")

    if assistant_text == "—":
        # LLM polish yoksa bile isteğe göre anlamlı default
        if intent_result.wants_alternatives:
            assistant_text = "Farklı seçenekler getirdim, aşağıdan seçebilirsin. İstersen tekrar ‘başka öner’ de."
        elif dish_hint == "dessert":
            assistant_text = "İstediğin tatlılar aşağıda. Beğenirsen tarife tıklayabilirsin."
        elif dish_hint == "soup":
            assistant_text = "Çorba önerilerim bunlar. İstersen başka öner deyebilirsin."
        elif dish_hint == "meze":
            assistant_text = "Meze ve atıştırmalık seçenekleri aşağıda."
        elif dish_hint == "breakfast":
            assistant_text = "Kahvaltılık tarifler aşağıda. İstersen birini seçip tarife geçebilirsin."
        elif dish_hint != "any" and dish_hint != "main":
            assistant_text = "İstediğin türe uygun tarifler aşağıda. Beğenirsen birini seç."
        elif inc_ings:
            assistant_text = f"{inc_ings[0].capitalize()} ile yapabileceğin tarifler aşağıda. Beğenirsen birini seç."
        else:
            assistant_text = "Senin için seçtiğim tarifler aşağıda. İstersen ‘başka öner’ diyerek yenilerini isteyebilirsin."

    # log suggestions for alternatives memory
    _log_suggested_recipes(db, session_uuid, [c["recipe_id"] for c in cards if c.get("recipe_id")])

    # save assistant msg
    db.add(ChatMessage(message_id=uuid.uuid4(), session_id=session_uuid, role="assistant", content=assistant_text))
    db.commit()

    result = {"session_id": str(session_uuid), "assistant_text": assistant_text, "cards": cards}
    if DEBUG_LLM_SOURCES:
        result["llm_sources"] = {"intent": intent_from_llm, "general_chat": False, "rerank": rerank_from_llm, "polish": polish_from_llm}
    return result