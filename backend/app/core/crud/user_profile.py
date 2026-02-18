from sqlalchemy.orm import Session
from sqlalchemy import select

from app.core.models.user_profile import UserProfile
from app.core.schemas.user_profile import UserProfileUpdate


def get_profile(db: Session, user_id):
    stmt = select(UserProfile).where(UserProfile.user_id == user_id)
    return db.execute(stmt).scalar_one_or_none()


def get_or_create_profile(db: Session, user_id):
    profile = get_profile(db, user_id)
    if profile is None:
        profile = UserProfile(user_id=user_id)
        db.add(profile)
        db.commit()
        db.refresh(profile)
    return profile


def upsert_profile(db: Session, user_id, payload: UserProfileUpdate):
    profile = get_or_create_profile(db, user_id)
    data = payload.model_dump(exclude_unset=True)

    for k, v in data.items():
        setattr(profile, k, v)

    db.commit()
    db.refresh(profile)
    return profile
