from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.schemas.user_profile import UserProfileOut, UserProfileUpdate
from app.core.crud.user_profile import get_or_create_profile, upsert_profile

router = APIRouter(prefix="/profile", tags=["profile"])


@router.get("", response_model=UserProfileOut)
def read_profile(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    return get_or_create_profile(db, current_user.user_id)


@router.put("", response_model=UserProfileOut)
def update_profile(
    payload: UserProfileUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    return upsert_profile(db, current_user.user_id, payload)
