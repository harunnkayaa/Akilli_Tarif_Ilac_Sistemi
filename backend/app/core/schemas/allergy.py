from pydantic import BaseModel, Field, model_validator


class AllergyCreate(BaseModel):
    # İKİ MOD:
    # 1) ingredient_id ile ekleme (ingredients tablosundan)
    # 2) raw_text ile ekleme (tarif malzemesi / serbest metin)
    ingredient_id: str | None = Field(default=None, min_length=1)
    raw_text: str | None = Field(default=None, min_length=1, max_length=120)
    reaction: str | None = Field(default=None, max_length=200)
    notes: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def validate_one_of(self):
        if (self.ingredient_id and self.raw_text) or (not self.ingredient_id and not self.raw_text):
            raise ValueError("ingredient_id_or_raw_text_required")
        return self


class AllergyOut(BaseModel):
    id: int
    ingredient_id: str | None = None

    # UI için gösterim:
    display_name: str

    raw_text: str | None = None
    is_custom: bool

    reaction: str | None = None
    notes: str | None = None

    class Config:
        from_attributes = True