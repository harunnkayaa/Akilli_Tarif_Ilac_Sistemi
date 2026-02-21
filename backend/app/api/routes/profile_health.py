from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.database import get_db

from app.core.schemas.disliked import DislikedIngredientOut, DislikedIngredientCreate
from app.core.schemas.allergy import AllergyOut, AllergyCreate
from app.core.schemas.disease import DiseaseOut, DiseaseCreate

from app.core.crud.disliked import list_disliked, add_disliked, remove_disliked
from app.core.crud.allergies import list_allergies, add_allergy, remove_allergy
from app.core.crud.diseases import list_diseases, add_disease, remove_disease

router = APIRouter(prefix="/profile", tags=["profile-health"])

# -------- disliked ingredients --------
@router.get("/disliked-ingredients", response_model=list[DislikedIngredientOut])
def get_disliked(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return list_disliked(db, current_user.user_id)

@router.post("/disliked-ingredients", response_model=DislikedIngredientOut)
def post_disliked(payload: DislikedIngredientCreate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return add_disliked(db, current_user.user_id, payload)

@router.delete("/disliked-ingredients/{ingredient_id}")
def delete_disliked(ingredient_id: str, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    remove_disliked(db, current_user.user_id, ingredient_id)
    return {"status": "ok"}

# -------- allergies --------
# -------- allergies --------
@router.get("/allergies", response_model=list[AllergyOut])
def get_allergies(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return list_allergies(db, current_user.user_id)

@router.post("/allergies", response_model=AllergyOut)
def post_allergy(payload: AllergyCreate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    try:
        return add_allergy(db, current_user.user_id, payload)
    except ValueError as e:
        # duplicate
        if str(e) == "already_exists":
            from fastapi import HTTPException
            raise HTTPException(status_code=409, detail="already exists")
        raise

@router.delete("/allergies/{allergy_id}")
def delete_allergy(allergy_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    remove_allergy(db, current_user.user_id, allergy_id)
    return {"status": "ok"}

# -------- diseases --------
@router.get("/diseases", response_model=list[DiseaseOut])
def get_diseases(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return list_diseases(db, current_user.user_id)

@router.post("/diseases", response_model=DiseaseOut)
def post_disease(payload: DiseaseCreate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return add_disease(db, current_user.user_id, payload)

@router.delete("/diseases/{disease_name}")
def delete_disease(disease_name: str, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    remove_disease(db, current_user.user_id, disease_name)
    return {"status": "ok"}
