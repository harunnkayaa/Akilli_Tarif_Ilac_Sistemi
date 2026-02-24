from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.schemas.intake import IntakeCreate, IntakeResult
from app.core.crud import intake as crud_intake
from app.api.deps import get_current_user


router = APIRouter(prefix="", tags=["intake"])


@router.post("/intake", response_model=IntakeResult)
def intake(
    payload: IntakeCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    try:
        idempotent, new_qty, remind_at = crud_intake.apply_intake(
            db=db,
            user_id=current_user.user_id,
            user_drug_id=payload.user_drug_id,
            client_event_id=payload.client_event_id,
            action=payload.action,
            scheduled_at=payload.scheduled_at,
            snooze_minutes=payload.snooze_minutes,
        )
        return IntakeResult(
            idempotent=idempotent,
            action=payload.action,
            user_drug_id=payload.user_drug_id,
            new_quantity=new_qty,
            remind_at=remind_at,
        )
    except ValueError as e:
        msg = str(e)
        if "not found" in msg.lower():
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=400, detail=msg)