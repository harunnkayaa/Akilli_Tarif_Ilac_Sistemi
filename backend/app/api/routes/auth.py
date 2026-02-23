from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy.orm import Session
import re
from app.core.database import get_db
from app.core.crud.users import get_user_by_email, create_user
from app.core.security import hash_password, verify_password, create_access_token

router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str):
        if not re.match(r"^(?=.*[A-Za-z])(?=.*\d).{8,}$", v):
            raise ValueError("password must be at least 8 chars and include letters and digits")
        return v


class RegisterOut(BaseModel):
    user_id: str
    email: EmailStr


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


@router.post("/register", response_model=RegisterOut)
def register(payload: RegisterIn, db: Session = Depends(get_db)):
    existing = get_user_by_email(db, payload.email)
    if existing:
        raise HTTPException(status_code=409, detail="email already registered")

    pw_hash = hash_password(payload.password)
    user = create_user(db, payload.email, pw_hash)
    return {"user_id": str(user.user_id), "email": user.email}


@router.post("/login", response_model=TokenOut)
def login(payload: LoginIn, db: Session = Depends(get_db)):
    user = get_user_by_email(db, payload.email)
    if not user:
        raise HTTPException(status_code=401, detail="invalid credentials")

    if not user.is_active:
        raise HTTPException(status_code=403, detail="user is inactive")

    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="invalid credentials")

    token = create_access_token(subject=str(user.user_id))
    return {"access_token": token, "token_type": "bearer"}
