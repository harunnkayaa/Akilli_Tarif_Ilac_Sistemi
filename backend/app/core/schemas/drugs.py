from __future__ import annotations

from datetime import date, time, datetime
from typing import List, Optional, Any, Dict
from uuid import UUID
from pydantic import BaseModel, Field


class ScheduleIn(BaseModel):
    time_of_day: time
    dose_text: Optional[str] = None
    days_mask: int = Field(default=127, ge=0)
    is_active: bool = True


class ScheduleOut(ScheduleIn):
    schedule_id: UUID

    class Config:
        from_attributes = True


class InventoryIn(BaseModel):
    quantity: int = Field(ge=0)
    unit: Optional[str] = None
    low_threshold: int = Field(ge=0)


class InventoryOut(InventoryIn):
    user_drug_id: UUID
    last_updated: datetime

    class Config:
        from_attributes = True


class UserDrugCreate(BaseModel):
    drug_name: str = Field(min_length=1)
    atc_code: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    notes: Optional[str] = None

    schedules: List[ScheduleIn] = Field(default_factory=list)
    inventory: Optional[InventoryIn] = None


class UserDrugUpdate(BaseModel):
    drug_name: Optional[str] = None
    atc_code: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    notes: Optional[str] = None

    schedules: Optional[List[ScheduleIn]] = None
    inventory: Optional[InventoryIn] = None


class UserDrugOut(BaseModel):
    user_drug_id: UUID
    user_id: UUID
    drug_name: str
    atc_code: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    notes: Optional[str] = None

    schedules: List[ScheduleOut] = Field(default_factory=list)
    inventory: Optional[InventoryOut] = None

    schedule_count_active: int = 0
    low_stock: bool = False

    class Config:
        from_attributes = True


InteractionRow = Dict[str, Any]