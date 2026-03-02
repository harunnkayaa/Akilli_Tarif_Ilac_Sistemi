"""
LLM (LangChain):
- Polisher: deterministic kartları profesyonel Türkçe ile anlatır + reason + warnings rewrite.
- General chat: kısa doğal sohbet.
"""
from __future__ import annotations

import json
import logging
import time
from typing import List, Dict, Any, Optional

from app.core.config import OPENAI_API_KEY, USE_RECIPE_LLM, OPENAI_CHAT_MODEL

logger = logging.getLogger(__name__)


def _chat_history_to_messages(chat_history: Optional[List[Dict[str, str]]]) -> List[Any]:
    from langchain_core.messages import HumanMessage, AIMessage
    out = []
    for m in (chat_history or [])[-10:]:
        role = (m.get("role") or "user").strip().lower()
        content = (m.get("content") or "").strip()
        if not content:
            continue
        out.append(AIMessage(content=content) if role == "assistant" else HumanMessage(content=content))
    return out


POLISHER_SYSTEM = """Sen bu uygulamanın TARİF ASİSTANI (Polisher) katmanısın.
Backend sana skorlanmış aday tarifleri ve kullanıcı mesajını veriyor. Kullanıcıya sadece cards_to_show_recipe_ids listesindeki tarifler gösterilecek.

assistant_text KURALLARI (önemli):
- Kullanıcının ne istediğine GÖNDERME yap: "tatlı" istediyse "İstediğin tatlılar aşağıda", "akşam yemeği" istediyse "Akşam yemeği için seçtiklerim bunlar", "patlıcanlı" istediyse "Patlıcanlı tariflerden seçtiklerim" gibi kısa ve anlamlı bir giriş yaz.
- Genel "İşte tarifler" yerine isteğe özel 1 cümle yaz. Sonra istersen "İstersen başka öner deyebilirsin" ekle.
- "başka öner" dediyse: "Farklı seçenekler getirdim, aşağıdan seçebilirsin" gibi.
- cards_to_show boşsa: "Bu isteğe uygun tarif bulamadım. Bizi uyardığın için teşekkürler." benzeri nazik mesaj.

Diğer kurallar:
- Yeni uyarı uydurma. Sadece verilen warnings'ı anlaşılır yaz.
- card_reasons: Her kart için 1 cümle neden (neden bu tarif isteğe uygun).
- warnings_rewritten: Sadece cards_to_show_recipe_ids içindeki tarifler için.
- Çıktı SADECE JSON. assistant_text, card_reasons, warnings_rewritten anahtarlarıyla dön.
"""


def _build_context_json(payload: Dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2)


def _parse_json(raw: str) -> Optional[Dict[str, Any]]:
    raw = (raw or "").strip()
    # code fence temizle
    if "```" in raw:
        start = raw.find("```")
        if start != -1:
            raw2 = raw[start+3:]
            end = raw2.find("```")
            raw = raw2[:end] if end != -1 else raw2
        raw = raw.replace("json", "", 1).strip()
    try:
        return json.loads(raw)
    except Exception as e:
        logger.warning("LLM JSON parse failed: %s | raw_preview=%r", e, raw[:400])
        return None


def _get_llm_json():
    from langchain_openai import ChatOpenAI
    return ChatOpenAI(
        model=OPENAI_CHAT_MODEL,
        temperature=0.35,  # şablon kırmak için 0.2 çok kısır kalıyor
        api_key=OPENAI_API_KEY,
        max_tokens=650,
        model_kwargs={"response_format": {"type": "json_object"}},
    )


GENERAL_SYSTEM = """Sen bir tarif uygulamasının sohbet asistanısın.
Kullanıcı selam/teşekkür gibi şeyler yazabilir.
Kısa, doğal cevap ver ve istersen 1 örnek kullanım öner.
Tarif önerisi KARTI üretme; sadece sohbet et."""


def generate_general_chat_response(
    user_message: str,
    chat_history: Optional[List[Dict[str, str]]] = None,
) -> Optional[str]:
    if not USE_RECIPE_LLM or not OPENAI_API_KEY:
        return None
    try:
        from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
        from langchain_openai import ChatOpenAI

        prompt = ChatPromptTemplate.from_messages([
            ("system", GENERAL_SYSTEM),
            MessagesPlaceholder("chat_history", optional=True),
            ("human", "{user_message}"),
        ])
        chain = prompt | ChatOpenAI(
            model=OPENAI_CHAT_MODEL,
            temperature=0.4,
            api_key=OPENAI_API_KEY,
            max_tokens=180,
        )
        resp = chain.invoke({"chat_history": _chat_history_to_messages(chat_history), "user_message": user_message or ""})
        txt = (resp.content if hasattr(resp, "content") else str(resp)).strip()
        return txt or None
    except Exception as e:
        logger.warning("general_chat failed: %s", e)
        return None


def generate_assistant_response(
    user_message: str,
    intent: Dict[str, Any],
    user_context: Dict[str, Any],
    stock_summary: Dict[str, Any],
    candidates: List[Dict[str, Any]],
    cards_to_show_recipe_ids: Optional[List[str]] = None,
    chat_history: Optional[List[Dict[str, str]]] = None,
) -> Optional[Dict[str, Any]]:
    """
    Polisher: assistant_text + card reasons + warnings rewrite.
    candidates: skorlanmış adaylar (örn. 15); card_reasons sadece cards_to_show_recipe_ids için.
    """
    if not USE_RECIPE_LLM or not OPENAI_API_KEY:
        return None

    payload = {
        "user_message": user_message,
        "intent": intent,
        "user_context": user_context,
        "stock_summary": stock_summary,
        "candidates": candidates,
        "cards_to_show_recipe_ids": cards_to_show_recipe_ids or [],
        "rules": {
            "no_new_warnings": True,
            "no_ranking_change": True,
        }
    }
    context_str = _build_context_json(payload)

    try:
        from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder

        prompt = ChatPromptTemplate.from_messages([
            ("system", POLISHER_SYSTEM),
            MessagesPlaceholder("chat_history", optional=True),
            ("human", "{context_json}"),
        ])

        t0 = time.perf_counter()
        chain = prompt | _get_llm_json()
        resp = chain.invoke({"chat_history": _chat_history_to_messages(chat_history), "context_json": context_str})
        latency_ms = (time.perf_counter() - t0) * 1000
        content = (resp.content if hasattr(resp, "content") else str(resp)).strip()

        parsed = _parse_json(content)
        if not parsed:
            return None

        parsed["meta"] = {"model": OPENAI_CHAT_MODEL, "latency_ms": round(latency_ms, 2), "provider": "langchain"}
        return parsed
    except Exception as e:
        logger.warning("polisher failed: %s", e, exc_info=True)
        return None