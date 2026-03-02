"""LLM debug: ping, durum."""
from fastapi import APIRouter
from app.core.config import USE_RECIPE_LLM, OPENAI_API_KEY, OPENAI_CHAT_MODEL

router = APIRouter(prefix="/llm", tags=["llm"])


@router.get("/ping")
def llm_ping():
    """LLM bağlı mı, hangi model (dev debug)."""
    return {
        "ok": True,
        "llm_enabled": bool(USE_RECIPE_LLM and OPENAI_API_KEY),
        "model": OPENAI_CHAT_MODEL or "gpt-4o-mini",
    }
