from pydantic import BaseModel, Field

class AllergyCreate(BaseModel):
    ingredient_id: str = Field(min_length=1)
    reaction: str | None = Field(default=None, max_length=200)
    notes: str | None = Field(default=None, max_length=500)

class AllergyOut(BaseModel):
    ingredient_id: str
    reaction: str | None = None
    notes: str | None = None

    class Config:
        from_attributes = True
