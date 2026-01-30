from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from pathlib import Path

app = FastAPI()

# ---- Static mount: /static -> backend/app/static klasörü ----
BASE_DIR = Path(__file__).resolve().parent  # backend/app
STATIC_DIR = BASE_DIR / "static"            # backend/app/static

app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

# ---- Test endpoint (server ayakta mı?) ----
@app.get("/health")
def health():
    return {"status": "ok"}
