from pathlib import Path
from app.core import models  # noqa: F401

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.api.router import api_router

app = FastAPI()

# ---- Static mount: /static -> backend/app/static ----
BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

app.include_router(api_router)
