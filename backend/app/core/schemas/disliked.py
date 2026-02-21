from pydantic import BaseModel, Field


class DislikedIngredientCreate(BaseModel):
    raw_text: str = Field(min_length=1, max_length=120)
    reason: str | None = Field(default=None, max_length=200)


class DislikedIngredientOut(BaseModel):
    id: int
    display_name: str
    reason: str | None = None

    class Config:
        from_attributes = True