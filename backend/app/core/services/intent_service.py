"""
Intent Extractor: LLM ile her kullanıcı mesajını parse eder.
- intent: recipe_request | general_chat
- dish_type: main|soup|dessert|meze|salad|breakfast|any
- include_ingredients / include_categories / exclude_categories
- rewrite_query (BOŞ OLMAZ)
- wants_alternatives / wants_cards
"""
from __future__ import annotations

import json
import logging
import time
from typing import List, Optional

from pydantic import BaseModel, Field

from app.core.config import OPENAI_API_KEY, USE_RECIPE_LLM, OPENAI_CHAT_MODEL

logger = logging.getLogger(__name__)


class IntentResult(BaseModel):
    intent: str = Field(description="recipe_request veya general_chat")
    dish_type: str = Field(default="any", description="main, soup, dessert, meze, salad, breakfast, any")
    include_ingredients: List[str] = Field(default_factory=list)
    exclude_ingredients: List[str] = Field(default_factory=list)
    exclude_categories: List[str] = Field(default_factory=list)
    include_categories: List[str] = Field(default_factory=list)
    rewrite_query: str = Field(default="", description="Retrieval için kısa Türkçe anahtar; BOŞ OLMAZ")
    wants_alternatives: bool = Field(default=False)
    wants_cards: bool = Field(default=False)
    mode: str = Field(default="auto", description="cook_now: stokuma göre | discover: keşfet | auto")


INTENT_SYSTEM_PROMPT = """Sen bir tarif sohbet asistanının niyet çıkarıcısısın. Görevin sadece kullanıcı mesajından niyet ve parametreleri çıkarmak; tarif önerisi veya tarif listesi ÜRETMEK DEĞİL.

ZORUNLU KURAL — Tarif kaynağı ve çıktı formatı:
- Tarif önerileri YALNIZCA uygulamanın kendi veritabanından gelecektir. Sen tarif adı, malzeme listesi veya tarif metni yazma; sadece niyet JSON'u döndür.
- Çıktın MUTLAKA geçerli JSON olmalı. Başka metin, açıklama veya markdown ekleme. Tek çıktı = tek JSON objesi.

Malzeme / içerik (include_ingredients):
- Kullanıcı belirli bir malzeme veya yemek türü istiyorsa MUTLAKA include_ingredients doldur.
- Kullanıcı belirli bir malzeme istemiyorsa (örn. sadece "akşam yemeği öner", "pratik bir şey") include_ingredients BOŞ bırak; o malzeme ve türevleriyle kısıtlama.
- Örnekler: "patlıcanlı yemek öner" -> include_ingredients=["patlıcan"], rewrite_query="patlıcanlı yemek"
- "tavuklu bir şey", "kıymalı yemek", "zerzevat öner", "balıklı tarif" -> ilgili malzemeyi include_ingredients'a ekle (örn. ["tavuk"], ["kıyma"], ["sebze"], ["balık"])
- "levrek var mı / levrekle ne yapabilirim" -> include_ingredients=["levrek"], rewrite_query="levrek tarifi"
- "içinde X olsun", "X'li olsun", "X ile yemek" -> include_ingredients=[X]
- Tek besin adı (patlıcan, kabak, mercimek, nohut vb.) geçiyorsa o besini include_ingredients'a ekle; rewrite_query'de de kullan.

Yemek türü (dish_type) — MUTLAKA doğru ver:
- "tatlı öner", "tatlı istiyorum", "tatlı tarifi", "şerbetli tatlı" -> dish_type=dessert, rewrite_query="tatlı" veya "şerbetli tatlı"
- "çorba öner", "çorba istiyorum" -> dish_type=soup
- "çorba değil yemek öner" -> dish_type=main, exclude_categories=["çorba"]
- "meze öner" -> dish_type=meze, include_categories=["meze","atıştırmalık"]
- "kahvaltılık" -> dish_type=breakfast
- "salata", "salata öner" -> dish_type=salad
- "akşam yemeği", "ana yemek", "yemek öner" (tür belirtilmemiş) -> dish_type=main veya any

Özel niyetler:
- "başka öner / farklı öner" -> recipe_request, wants_alternatives=true
- "seçenekleri göster / kartları göster" -> recipe_request, wants_cards=true
- "stokuma göre / hemen yapabileceğim" -> recipe_request, mode=cook_now
- "keşfet / genel öner" -> recipe_request, mode=discover
- Sadece selam/teşekkür (başka kelime yok) -> intent=general_chat
- Yemek, tarif, malzeme veya öneri geçen her mesaj -> intent=recipe_request

mode: cook_now | discover | auto. rewrite_query asla boş bırakma; recipe_request ise mutlaka doldur.

ÇIKTI: Yalnızca JSON. intent anahtarı (string) zorunlu; değer "recipe_request" veya "general_chat". general_chat için bile doğru anahtarla JSON dön; rewrite_query boş olabilir. Başka metin yazma.
"""


def _chat_history_to_langchain_messages(chat_history: Optional[List[dict]]) -> List:
    from langchain_core.messages import HumanMessage, AIMessage
    out = []
    for m in (chat_history or [])[-10:]:
        role = (m.get("role") or "user").strip().lower()
        content = (m.get("content") or "").strip()
        if not content:
            continue
        out.append(AIMessage(content=content) if role == "assistant" else HumanMessage(content=content))
    return out


def _get_intent_llm():
    from langchain_openai import ChatOpenAI
    return ChatOpenAI(
        model=OPENAI_CHAT_MODEL,
        temperature=0.1,
        api_key=OPENAI_API_KEY,
        max_tokens=350,
        model_kwargs={"response_format": {"type": "json_object"}},
    )


def _normalize_intent_json(raw: dict) -> dict:
    """LLM bazen intent yerine general_chat/recipe_request döner; bunu intent string + düz dict yapar."""
    if not isinstance(raw, dict):
        return raw
    out = dict(raw)
    if "intent" not in out or not isinstance(out.get("intent"), str):
        if raw.get("general_chat") is True:
            out["intent"] = "general_chat"
        elif raw.get("recipe_request") is True or isinstance(raw.get("recipe_request"), dict):
            out["intent"] = "recipe_request"
            if isinstance(raw.get("recipe_request"), dict):
                for k, v in raw["recipe_request"].items():
                    if k != "intent" and k not in out:
                        out[k] = v
        else:
            out["intent"] = "recipe_request"
    out.pop("general_chat", None)
    out.pop("recipe_request", None)
    return out


def _get_intent_prompt_chain():
    from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
    return ChatPromptTemplate.from_messages([
        ("system", INTENT_SYSTEM_PROMPT),
        MessagesPlaceholder("chat_history", optional=True),
        ("human", "Son kullanıcı mesajı: {user_message}\nSon önerilen tarif id'leri: {last_cards}\nJSON ver."),
    ])


def extract_intent(
    user_message: str,
    chat_history: Optional[List[dict]] = None,
    last_cards: Optional[List[str]] = None,
):
    """Returns (IntentResult, used_llm: bool). used_llm True ise niyet LLM'den geldi."""
    msg = (user_message or "").strip()

    # fallback: asla "hazır paragraf" tuzağına düşürmeyecek şekilde
    fb = IntentResult(
        intent="general_chat" if _looks_like_greeting_only(msg) else "recipe_request",
        dish_type="any",
        rewrite_query=(msg[:200] if msg else "tarif öner"),
    )
    _apply_light_fallback_hints(msg, fb)

    if not USE_RECIPE_LLM or not OPENAI_API_KEY:
        logger.info("LLM intent: fallback (USE_RECIPE_LLM veya OPENAI_API_KEY yok)")
        return fb, False

    try:
        prompt = _get_intent_prompt_chain()
        history_messages = _chat_history_to_langchain_messages(chat_history)
        chain = prompt | _get_intent_llm()

        t0 = time.perf_counter()
        resp = chain.invoke({
            "chat_history": history_messages,
            "user_message": msg,
            "last_cards": (last_cards or [])[:5],
        })
        latency_ms = (time.perf_counter() - t0) * 1000
        content = (resp.content if hasattr(resp, "content") else str(resp)).strip()
        parsed = json.loads(content) if content else {}
        parsed = _normalize_intent_json(parsed)
        out = IntentResult(**{k: v for k, v in parsed.items() if k in IntentResult.model_fields})

        if not (out.rewrite_query or "").strip():
            out.rewrite_query = (msg[:200] if msg else "tarif öner")

        logger.info("LLM intent: llm intent=%s dish=%s latency=%.0fms",
                    out.intent, out.dish_type, latency_ms)
        return out, True
    except Exception as e:
        logger.warning("LLM intent: fallback (hata: %s)", e)
        return fb, False


def _looks_like_greeting_only(msg: str) -> bool:
    if not msg:
        return True
    norm = _norm(msg)
    greetings = {"selam","merhaba","hey","hi","hello","gunaydin","iyi geceler","iyi aksamlar",
                 "tesekkur","tesekkurler","sagol","sagolun","naber","eyvallah"}
    tokens = set(norm.split())
    return (norm in greetings) or (tokens and tokens <= greetings)


def _apply_light_fallback_hints(msg: str, fb: IntentResult) -> None:
    """LLM yoksa bile: levrek/meze/çorba değil gibi şeylerde saçmalamasın."""
    norm = _norm(msg)
    if not norm:
        return

    if any(x in norm for x in ("baska oner", "farkli oner", "ayni olmasin", "degisik oner")):
        fb.intent = "recipe_request"
        fb.wants_alternatives = True

    if any(x in norm for x in ("kartlari goster", "secenekleri goster", "listele", "secenek")):
        fb.intent = "recipe_request"
        fb.wants_cards = True

    if "corba" in norm and any(x in norm for x in ("degil", "istemiyorum", "olmasin", "istemem")):
        fb.intent = "recipe_request"
        fb.dish_type = "main"
        fb.exclude_categories = ["çorba"]

    if any(x in norm for x in ("meze", "aperatif", "atistirmalik", "baslangic")):
        fb.intent = "recipe_request"
        fb.dish_type = "meze"
        fb.include_categories = ["meze", "atıştırmalık"]

    if "tatli" in norm and any(k in norm for k in ("oner", "istiyorum", "tarifi", "serbetli", "yemek", "ne ")):
        fb.intent = "recipe_request"
        fb.dish_type = "dessert"
        if not fb.rewrite_query or fb.rewrite_query == msg[:200]:
            fb.rewrite_query = "tatlı"

    # ingredient fallback (LLM yoksa): "X'li yemek" / "X öner" kalıpları ve yaygın malzemeler
    for ing in ("levrek","somon","hamsi","cipura","çipura","balik","balık","tavuk","brokoli","patlican","patlıcan","kabak","mercimek","nohut","kıyma","kiyma","domates","biber","soğan","sogan"):
        if ing in norm:
            fb.intent = "recipe_request"
            name = ing.replace("cipura","çipura").replace("balik","balık").replace("patlican","patlıcan").replace("sogan","soğan").replace("kiyma","kıyma")
            fb.include_ingredients = [name]
            if not fb.rewrite_query or fb.rewrite_query == msg[:200]:
                fb.rewrite_query = f"{name} tarifi"


def _norm(s: str) -> str:
    s = (s or "").lower().strip()
    for a, b in (("ş", "s"), ("ğ", "g"), ("ı", "i"), ("ö", "o"), ("ü", "u"), ("ç", "c")):
        s = s.replace(a, b)
    return s