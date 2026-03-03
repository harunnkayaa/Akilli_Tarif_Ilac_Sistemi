from typing import List, Optional, Union
from pydantic import BaseModel, Field, field_validator


class RecipeChatSuggestRequest(BaseModel):
    """Mod: 1 veya "discover" = stok durumu olmadan öneri, 2 veya "cook_now" = stok durumuna göre öneri."""
    session_id: Optional[str] = None
    message: str = Field(..., min_length=1, max_length=2000)
    mode: Optional[str] = Field(None, description="1 | 2 veya discover | cook_now")

    @field_validator("mode", mode="before")
    @classmethod
    def normalize_mode(cls, v):
        if v is None:
            return None
        if isinstance(v, int):
            return "cook_now" if v == 2 else "discover"  # 1 -> discover, 2 -> cook_now
        if isinstance(v, str):
            s = v.strip().lower()
            if s in ("discover", "cook_now"):
                return s
            if s == "2":
                return "cook_now"
            if s == "1":
                return "discover"
        return None


class RecipeCardOut(BaseModel):
    recipe_id: str
    title: str
    image_url: Optional[str] = None
    reason: str
    warnings: List[str] = Field(default_factory=list)
    badges: List[str] = Field(default_factory=list)
    missing_ingredients: List[str] = Field(default_factory=list, description="Eksik zorunlu malzemeler (staple hariç)")
    available_ingredients: List[str] = Field(default_factory=list, description="Stokta olan zorunlu malzemeler (staple hariç)")
    # DEBUG_RECIPE_SCORING=1 iken doldurulur
    debug_msg_score: Optional[float] = None
    debug_pantry_score: Optional[float] = None
    debug_stock_match_score: Optional[float] = None
    debug_final_score: Optional[float] = None
    debug_nonstaple_total_g_ml: Optional[float] = None
    debug_nonstaple_matched_sum: Optional[float] = None


class LLMSourcesOut(BaseModel):
    """DEBUG_LLM_SOURCES=1 iken hangi cevapların LLM'den geldiği."""
    intent: bool = False
    general_chat: bool = False
    rerank: bool = False
    polish: bool = False


class RecipeChatSuggestResponse(BaseModel):
    session_id: str
    assistant_text: str
    cards: List[RecipeCardOut] = Field(default_factory=list)
    llm_sources: Optional[LLMSourcesOut] = Field(None, description="DEBUG_LLM_SOURCES=1 iken dolu")


class CookAddPantryItem(BaseModel):
    ingredient_id: str
    quantity: float
    low_threshold: Optional[float] = Field(default=None, ge=0, description="Eşik (gram); stok bu değerin altına düşünce uyarı")


class CookRecipeRequest(BaseModel):
    """Eksik malzemeleri stoka ekleyip pişirmek için."""
    add_pantry: Optional[List[CookAddPantryItem]] = Field(default=None, description="Stoka eklenecek malzemeler (gram)")


class CookRecipeResponse(BaseModel):
    success: bool
    error: Optional[str] = None
    missing: Optional[List[str]] = None
    daily_nutrient_totals: Optional[dict] = None


class RecipeIngredientOut(BaseModel):
    name: str
    unit: Optional[str] = Field(default=None, description="Birim (g, ml, adet vb.)")
    amount: Optional[float] = Field(default=None, description="Standart_Miktar (sayısal)")
    display_amount: Optional[str] = Field(default=None, description="Tarif_Olcum, kullanıcıya gösterilecek ölçü")


class RecipeDetailResponse(BaseModel):
    recipe_id: str
    title: str
    category: Optional[str] = None
    servings: Optional[int] = None
    total_calories_kcal: Optional[float] = None
    calories_per_serving_kcal: Optional[float] = None
    source_url: Optional[str] = None
    image_url: Optional[str] = None
    steps: Optional[str] = Field(default=None, description="tarif_adimlari serbest metin")
    ingredients: List[RecipeIngredientOut] = Field(default_factory=list)
