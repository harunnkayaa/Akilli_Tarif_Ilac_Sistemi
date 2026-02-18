from uuid import uuid4
from sqlalchemy.orm import Session
from sqlalchemy import select

from app.core.models.user import User


def get_user_by_email(db: Session, email: str):
    stmt = select(User).where(User.email == email)
    return db.execute(stmt).scalar_one_or_none()


def get_user_by_id(db: Session, user_id):
    stmt = select(User).where(User.user_id == user_id)
    return db.execute(stmt).scalar_one_or_none()


def create_user(db: Session, email: str, password_hash: str):
    user = User(
        user_id=uuid4(),   # ✅ PK burada üretilecek
        email=email,
        password_hash=password_hash,
        is_active=True,    # DB defaultuna güvenme, açık yaz
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user
