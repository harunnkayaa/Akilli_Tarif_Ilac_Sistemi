import logging
from pathlib import Path
from app.core import models  # noqa: F401

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.api.router import api_router
from app.core.config import USE_RECIPE_LLM, OPENAI_API_KEY

logger = logging.getLogger(__name__)

app = FastAPI()


@app.on_event("startup")
def _log_llm_status():
    """Backend ayağa kalkarken LLM bağlı mı logla."""
    if USE_RECIPE_LLM and OPENAI_API_KEY:
        logger.info("LLM recipe: ENABLED (USE_RECIPE_LLM=1, OPENAI_API_KEY set)")
    else:
        logger.info("LLM recipe: DISABLED (USE_RECIPE_LLM=%s, OPENAI_API_KEY=%s)", USE_RECIPE_LLM, "set" if OPENAI_API_KEY else "not set")

# ---- Static mount: /static -> backend/app/static ----
BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

app.include_router(api_router)
