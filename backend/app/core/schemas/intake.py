from __future__ import annotations

from datetime import datetime
from typing import Optional, Literal
from uuid import UUID
from pydantic import BaseModel, Field


IntakeAction = Literal["TAKEN", "SNOOZE", "SKIP", "MISSED"]


class IntakeCreate(BaseModel):
    user_drug_id: UUID
    client_event_id: str = Field(min_length=1, max_length=200)
    action: IntakeAction

    # client gönderiyor (notification schedule time gibi), tz-aware ISO beklenir
    scheduled_at: Optional[datetime] = None

    # SNOOZE default 5dk (frontend de 5dk yapacak) ama backend kaydı için saniye bazlı.
    snooze_minutes: int = Field(default=5, ge=1, le=120)


class IntakeResult(BaseModel):
    idempotent: bool
    action: IntakeAction
    user_drug_id: UUID
    new_quantity: Optional[int] = None
    remind_at: Optional[datetime] = None
    stock_depleted: bool = False