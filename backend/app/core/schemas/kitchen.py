# backend/app/core/schemas/kitchen.py  (TEMİZ VE TEK TANIM)
from datetime import date, datetime
from typing import Literal, Optional
from uuid import UUID
from pydantic import BaseModel, Field, field_validator

# ---------- Pantry ----------
class PantryUpsertIn(BaseModel):
    ingredient_id: str
    quantity: float = Field(ge=0)
    unit: str  # g | ml
    expires_at: Optional[date] = None
    low_threshold: Optional[float] = Field(default=None, ge=0)
    mode: Literal["add", "set"] = "add"

    @field_validator("ingredient_id")
    @classmethod
    def _name_required(cls, v: str):
        v = (v or "").strip()
        if not v:
            raise ValueError("ingredient_id cannot be empty")
        return v

    @field_validator("unit")
    @classmethod
    def _unit_only(cls, v: str):
        v = (v or "").strip().lower()
        if v not in ("g", "ml"):
            raise ValueError("unit must be g or ml")
        return v

class PantryItemOut(BaseModel):
    user_id: UUID
    ingredient_id: str
    quantity: float
    unit: Optional[str]
    expires_at: Optional[date]
    low_threshold: Optional[float]
    updated_at: datetime

    class Config:
        from_attributes = True

class PantryAlertOut(BaseModel):
    ingredient_id: str
    quantity: float
    low_threshold: Optional[float]
    status: str

# ---------- Shopping List ----------
class ShoppingManualAddIn(BaseModel):
    item_text: str
    target_qty: Optional[float] = Field(default=None, ge=0)
    unit: Optional[str] = None

class ShoppingItemOut(BaseModel):
    item_id: UUID
    user_id: UUID
    ingredient_id: Optional[str]
    item_text: Optional[str]
    target_qty: Optional[float]
    unit: Optional[str]
    is_checked: bool
    created_at: datetime

    class Config:
        from_attributes = True

class ShoppingCheckIn(BaseModel):
    is_checked: bool