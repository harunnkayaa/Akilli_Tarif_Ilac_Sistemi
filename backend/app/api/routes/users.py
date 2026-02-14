from fastapi import APIRouter, Depends
from pydantic import BaseModel, EmailStr

from app.api.deps import get_current_user

router = APIRouter(prefix="/users", tags=["users"])

class MeOut(BaseModel):
    user_id: str
    email: EmailStr
    is_active: bool

@router.get("/me", response_model=MeOut)
def me(user=Depends(get_current_user)):
    return {
        "user_id": str(user["user_id"]),
        "email": user["email"],
        "is_active": user["is_active"],
    }
