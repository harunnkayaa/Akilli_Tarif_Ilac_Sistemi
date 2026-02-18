from datetime import date
from pydantic import BaseModel, Field

class DiseaseCreate(BaseModel):
    disease_name: str = Field(min_length=2, max_length=120)
    diagnosed_at: date | None = None
    notes: str | None = Field(default=None, max_length=500)

class DiseaseOut(BaseModel):
    disease_name: str
    diagnosed_at: date | None = None
    notes: str | None = None

    class Config:
        from_attributes = True
