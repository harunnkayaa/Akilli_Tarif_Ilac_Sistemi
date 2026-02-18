from datetime import datetime
from decimal import Decimal
from uuid import UUID
from pydantic import BaseModel, Field, field_validator

ALLOWED_GENDER = {"male", "female"}




class UserProfileOut(BaseModel):
    user_id: UUID
    full_name: str | None = None
    birth_year: int | None = None
    gender: str | None = None
    height_cm: int | None = Field(default=None, ge=40, le=260)
    weight_kg: Decimal | None = Field(default=None, ge=Decimal("2"), le=Decimal("400"))
    created_at: datetime
    updated_at: datetime


class UserProfileUpdate(BaseModel):
    full_name: str | None = Field(default=None, max_length=120)
    birth_year: int | None = None
    gender: str | None = None
    height_cm: int | None = Field(default=None, ge=40, le=260)
    weight_kg: Decimal | None = Field(default=None, ge=Decimal("2"), le=Decimal("400"))

    @field_validator("gender")
    @classmethod
    def validate_gender(cls, v):
        if v is None:
            return v
        v2 = v.strip().lower()
        if v2 == "":
            return None
        if v2 not in ALLOWED_GENDER:
            raise ValueError(f"gender must be one of {sorted(ALLOWED_GENDER)}")
        return v2


    @field_validator("birth_year")
    @classmethod
    def validate_birth_year(cls, v):
        if v is None:
            return v
        from datetime import datetime
        year = datetime.utcnow().year
        if v < 1900 or v > year:
            raise ValueError("birth_year must be between 1900 and current year")
        return v
