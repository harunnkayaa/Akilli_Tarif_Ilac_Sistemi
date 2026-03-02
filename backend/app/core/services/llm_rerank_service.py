"""
LLM Reranker: 200-300 aday içinden intent + mode'a göre en uygun 40 id seçer (talimat).
- Candidate format: recipe_id, title, category, short_ingredients, rag_score, stock_match_score
- mode: cook_now (stok ağırlıklı) | discover (keşfet)
"""
from __future__ import annotations

import json
import logging
import time
from typing import List, Dict, Any, Optional

from app.core.config import OPENAI_API_KEY, USE_RECIPE_LLM, OPENAI_CHAT_MODEL, LLM_RERANK_K

logger = logging.getLogger(__name__)

RERANK_SYSTEM = """Sen bir tarif öneri sisteminde RERANK asistanısın.
Sana kullanıcı mesajı, mode, dish_type, include_ingredients ve aday tarif listesi (her tarifin recipe_id, title, category, short_ingredients, rag_score, stock_match_score) verilecek.
Görevin: Kullanıcının isteğine GERÇEKTEN UYGUN tarifleri seçmek.

ZORUNLU KURALLAR:
1) SADECE verilen adaylar arasından seç. selected_recipe_ids listesine en uygun 40'a kadar id yaz.
2) include_ingredients dolu ise (örn. ["patlıcan"], ["tavuk"]): SADECE short_ingredients veya title/category içinde o malzeme GEÇEN tarifleri seç. İstenen malzemeyi içermeyen tarifi ASLA seçme. Örn. kullanıcı "patlıcanlı yemek" dediyse patlıcan içermeyen tarif seçme.
3) dish_type ZORUNLU: dish_type=dessert ise SADECE category/title içinde "tatlı" geçen tarifleri seç (ana yemek/ızgara/çorba ASLA seçme). dish_type=soup ise sadece çorba, meze ise sadece meze. Yanlış tür seçme.
4) mode=cook_now ise stok uyumu (stock_match_score) önemli; mode=discover ise stok DİKKATE ALINMAZ, sadece rag_score ve niyet.
5) Önce kullanıcı isteğine uyan tarifleri filtrele (özellikle include_ingredients), sonra en iyilerini seç.
6) Yanıt SADECE geçerli JSON: selected_recipe_ids adlı listede id'leri yaz, notes adlı kısa string ile dön. (Anahtar adları: selected_recipe_ids ve notes.)"""

def _get_llm():
    from langchain_openai import ChatOpenAI
    return ChatOpenAI(
        model=OPENAI_CHAT_MODEL,
        temperature=0.1,
        api_key=OPENAI_API_KEY,
        max_tokens=450,
        model_kwargs={"response_format": {"type": "json_object"}},
    )

def _parse_json(raw: str) -> Optional[Dict[str, Any]]:
    raw = (raw or "").strip()
    if "```" in raw:
        # codeblock temizle
        start = raw.find("```")
        raw2 = raw[start+3:]
        if raw2.lstrip().startswith("json"):
            raw2 = raw2.lstrip()[4:]
        end = raw2.find("```")
        raw = raw2[:end] if end != -1 else raw2
        raw = raw.strip()
    try:
        return json.loads(raw)
    except Exception:
        return None

def rerank_recipe_ids(
    user_message: str,
    intent: Dict[str, Any],
    user_context: Dict[str, Any],
    stock_summary: Dict[str, Any],
    candidates: List[Dict[str, Any]],
    avoid_ids: Optional[List[str]] = None,
    top_m: int = None,
) -> Optional[Dict[str, Any]]:
    if not USE_RECIPE_LLM or not OPENAI_API_KEY:
        return None
    if not candidates:
        return None

    top_m = int(top_m or LLM_RERANK_K or 40)
    cand = (candidates or [])[:300]
    avoid = set(str(x) for x in (avoid_ids or []) if x)
    inc_ing = (intent or {}).get("include_ingredients") or []

    payload = {
        "user_message": user_message or "",
        "mode": (intent or {}).get("mode") or "discover",
        "dish_type": (intent or {}).get("dish_type") or "any",
        "include_ingredients": inc_ing,
        "exclude_categories": (intent or {}).get("exclude_categories") or [],
        "user_context": user_context or {},
        "pantry_summary": (stock_summary or {}).get("pantry_summary") or (stock_summary or {}).get("top_items") or [],
        "candidates": cand,
        "top_m": top_m,
        "output_format": {"selected_recipe_ids": ["id1", "id2"], "notes": "kısa"},
    }
    if inc_ing:
        payload["_instruction"] = f"ÖNEMLİ: Kullanıcı şu malzemeyi/malzemeleri istiyor: {inc_ing}. Sadece short_ingredients veya title içinde bunlardan en az birini içeren tarifleri seç. İçermeyen tarifleri listeye EKLEME."

    def _json_safe(obj):
        if obj is ... or type(obj).__name__ == "ellipsis":
            return None
        if isinstance(obj, dict):
            return {k: _json_safe(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [_json_safe(x) for x in obj]
        return obj

    try:
        from langchain_core.prompts import ChatPromptTemplate
        prompt = ChatPromptTemplate.from_messages([
            ("system", RERANK_SYSTEM),
            ("human", "{payload_json}"),
        ])
        chain = prompt | _get_llm()

        t0 = time.perf_counter()
        resp = chain.invoke({"payload_json": json.dumps(_json_safe(payload), ensure_ascii=False)})
        latency_ms = (time.perf_counter() - t0) * 1000

        content = (resp.content if hasattr(resp, "content") else str(resp)).strip()
        parsed = _parse_json(content)
        if not parsed or "selected_recipe_ids" not in parsed:
            logger.warning("LLM rerank parse failed. raw_preview=%r", content[:400])
            return None

        ids = [str(x) for x in (parsed.get("selected_recipe_ids") or []) if x]
        # avoid ids clean
        ids = [x for x in ids if x not in avoid]
        # dedup preserve order
        seen = set()
        ids2 = []
        for x in ids:
            if x in seen:
                continue
            seen.add(x)
            ids2.append(x)
        parsed["selected_recipe_ids"] = ids2[:top_m]
        parsed["meta"] = {"latency_ms": round(latency_ms, 2), "model": OPENAI_CHAT_MODEL, "provider": "langchain"}
        return parsed
    except Exception as e:
        logger.warning("LLM rerank failed: %s", e, exc_info=True)
        return None