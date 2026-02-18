from pydantic import BaseModel, Field

class DislikedIngredientCreate(BaseModel):
    ingredient_id: str = Field(min_length=1)
    reason: str | None = Field(default=None, max_length=200)

class DislikedIngredientOut(BaseModel):
    ingredient_id: str
    reason: str | None = None

    class Config:
        from_attributes = True
