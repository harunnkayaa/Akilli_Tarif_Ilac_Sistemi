from pydantic import BaseModel

class IngredientOut(BaseModel):
    id: str
    canonical_name_tr: str | None = None

    class Config:
        from_attributes = True
