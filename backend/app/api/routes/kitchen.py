# backend/app/api/routes/kitchen.py  (SHOPPING'TEN DÜŞÜRME + MODE PASS)
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from uuid import UUID

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.schemas.kitchen import (
    PantryUpsertIn, PantryItemOut, PantryAlertOut,
    ShoppingManualAddIn, ShoppingItemOut, ShoppingCheckIn
)
from app.core.crud import kitchen as kitchen_crud

router = APIRouter(prefix="/kitchen", tags=["kitchen"])

@router.get("/pantry", response_model=list[PantryItemOut])
def get_pantry(db: Session = Depends(get_db), user=Depends(get_current_user)):
    return kitchen_crud.list_pantry(db, user.user_id)

@router.post("/pantry", response_model=PantryItemOut)
def upsert_pantry(payload: PantryUpsertIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
    item = kitchen_crud.upsert_pantry_item(
        db,
        user_id=user.user_id,
        ingredient_id=payload.ingredient_id,
        quantity=payload.quantity,
        unit=payload.unit,
        expires_at=payload.expires_at,
        low_threshold=payload.low_threshold,
        mode=payload.mode,
    )

    qty = float(item.quantity or 0)
    low = float(item.low_threshold) if item.low_threshold is not None else None

    # ✅ stok artık yeterliyse: alışveriş listesinden düşür
    if qty > 0 and (low is None or qty > low):
        kitchen_crud._delete_auto_shopping_if_exists(db, user.user_id, item.ingredient_id)

    # ✅ kritik/bitti ise: auto ekle
    if qty <= 0 or (low is not None and qty <= low):
        kitchen_crud.ensure_auto_item_exists(
            db,
            user_id=user.user_id,
            ingredient_id=item.ingredient_id,
            unit=item.unit,
            target_qty=low,
        )

    db.commit()
    db.refresh(item)
    return item

@router.delete("/pantry/{ingredient_id}")
def delete_pantry(ingredient_id: str, db: Session = Depends(get_db), user=Depends(get_current_user)):
    ok = kitchen_crud.delete_pantry_item(db, user.user_id, ingredient_id)
    if not ok:
        raise HTTPException(status_code=404, detail="pantry item not found")
    db.commit()
    return {"status": "deleted"}

@router.get("/pantry/alerts", response_model=list[PantryAlertOut])
def pantry_alerts(db: Session = Depends(get_db), user=Depends(get_current_user)):
    return kitchen_crud.get_pantry_alerts(db, user.user_id)

@router.get("/shopping-list", response_model=list[ShoppingItemOut])
def get_shopping(db: Session = Depends(get_db), user=Depends(get_current_user)):
    return kitchen_crud.list_shopping(db, user.user_id)

@router.post("/shopping-list/manual", response_model=ShoppingItemOut)
def add_manual(payload: ShoppingManualAddIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
    item = kitchen_crud.add_manual_shopping_item(db, user.user_id, payload.item_text, payload.target_qty, payload.unit)
    db.commit()
    db.refresh(item)
    return item

@router.post("/shopping-list/refresh")
def refresh(db: Session = Depends(get_db), user=Depends(get_current_user)):
    result = kitchen_crud.refresh_shopping_from_pantry(db, user.user_id)
    db.commit()
    return {"status": "ok", **result}

@router.put("/shopping-list/{item_id}")
def set_item_checked(item_id: UUID, payload: ShoppingCheckIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
    ok = kitchen_crud.set_checked(db, user.user_id, item_id, payload.is_checked)
    if not ok:
        raise HTTPException(status_code=404, detail="shopping item not found")
    db.commit()
    return {"status": "ok"}

@router.delete("/shopping-list/{item_id}")
def delete_item(item_id: UUID, db: Session = Depends(get_db), user=Depends(get_current_user)):
    ok = kitchen_crud.delete_shopping_item(db, user.user_id, item_id)
    if not ok:
        raise HTTPException(status_code=404, detail="shopping item not found")
    db.commit()
    return {"status": "deleted"}