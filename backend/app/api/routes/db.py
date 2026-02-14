"""DB ping router."""
from fastapi import APIRouter, HTTPException
from app.core.database import db_ping

router = APIRouter(prefix="/db", tags=["db"])


@router.get("/ping")
def db_ping_route():
    try:
        db_ping()
    except Exception:
        raise HTTPException(status_code=503, detail="db unavailable")
    return {"db": "ok"}
