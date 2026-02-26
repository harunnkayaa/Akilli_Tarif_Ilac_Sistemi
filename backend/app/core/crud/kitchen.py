# backend/app/core/crud/kitchen.py  (MODE=ADD + STOCK ARTTIYSA SHOPPING'TEN DÜŞÜR)
from typing import List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from app.core.models.pantry_items import PantryItem
from app.core.models.shopping_list_items import ShoppingListItem

def list_pantry(db: Session, user_id) -> List[PantryItem]:
    return (
        db.query(PantryItem)
        .filter(PantryItem.user_id == user_id)
        .order_by(PantryItem.ingredient_id.asc())
        .all()
    )

def _delete_auto_shopping_if_exists(db: Session, user_id, ingredient_id: str):
    # unchecked auto satırı sil (ingredient_id dolu olan)
    q = (
        db.query(ShoppingListItem)
        .filter(
            and_(
                ShoppingListItem.user_id == user_id,
                ShoppingListItem.ingredient_id == ingredient_id,
                ShoppingListItem.is_checked == False,  # noqa: E712
            )
        )
    )
    for it in q.all():
        db.delete(it)

def upsert_pantry_item(
    db: Session,
    user_id,
    ingredient_id: str,
    quantity: float,
    unit: Optional[str],
    expires_at,
    low_threshold: Optional[float],
    mode: str = "add",
) -> PantryItem:
    item = (
        db.query(PantryItem)
        .filter(and_(PantryItem.user_id == user_id, PantryItem.ingredient_id == ingredient_id))
        .first()
    )

    if item is None:
        item = PantryItem(
            user_id=user_id,
            ingredient_id=ingredient_id,
            quantity=quantity,
            unit=unit,
            expires_at=expires_at,
            low_threshold=low_threshold,
        )
        db.add(item)
        db.flush()
        return item

    # mevcut var
    if mode == "add":
        item.quantity = float(item.quantity or 0) + float(quantity or 0)
    else:  # set
        item.quantity = quantity

    item.unit = unit
    item.expires_at = expires_at
    item.low_threshold = low_threshold

    db.flush()
    return item

def delete_pantry_item(db: Session, user_id, ingredient_id: str) -> bool:
    item = (
        db.query(PantryItem)
        .filter(and_(PantryItem.user_id == user_id, PantryItem.ingredient_id == ingredient_id))
        .first()
    )
    if not item:
        return False
    db.delete(item)
    # stok silindiyse auto shopping de temizle
    _delete_auto_shopping_if_exists(db, user_id, ingredient_id)
    return True

def get_pantry_alerts(db: Session, user_id):
    items = db.query(PantryItem).filter(PantryItem.user_id == user_id).all()
    alerts = []
    for it in items:
        low = float(it.low_threshold) if it.low_threshold is not None else None
        qty = float(it.quantity or 0)

        if qty <= 0:
            alerts.append({"ingredient_id": it.ingredient_id, "quantity": qty, "low_threshold": low, "status": "OUT"})
        elif low is not None and qty <= low:
            alerts.append({"ingredient_id": it.ingredient_id, "quantity": qty, "low_threshold": low, "status": "LOW"})
    return alerts

def list_shopping(db: Session, user_id) -> List[ShoppingListItem]:
    return (
        db.query(ShoppingListItem)
        .filter(ShoppingListItem.user_id == user_id)
        .order_by(ShoppingListItem.is_checked.asc(), ShoppingListItem.created_at.desc())
        .all()
    )

def add_manual_shopping_item(db: Session, user_id, item_text: str, target_qty: Optional[float], unit: Optional[str]):
    # aynı text unchecked ise target_qty biriktir
    existing = (
        db.query(ShoppingListItem)
        .filter(
            and_(
                ShoppingListItem.user_id == user_id,
                ShoppingListItem.item_text == item_text,
                ShoppingListItem.is_checked == False,  # noqa: E712
            )
        )
        .first()
    )
    if existing:
        if target_qty is not None:
            existing.target_qty = float(existing.target_qty or 0) + float(target_qty)
        if existing.unit is None and unit is not None:
            existing.unit = unit
        db.flush()
        return existing

    item = ShoppingListItem(
        user_id=user_id,
        ingredient_id=None,
        item_text=item_text,
        target_qty=target_qty,
        unit=unit,
        is_checked=False,
    )
    db.add(item)
    db.flush()
    return item

def ensure_auto_item_exists(db: Session, user_id, ingredient_id: str, unit: Optional[str], target_qty: Optional[float]):
    existing = (
        db.query(ShoppingListItem)
        .filter(
            and_(
                ShoppingListItem.user_id == user_id,
                ShoppingListItem.ingredient_id == ingredient_id,
                ShoppingListItem.is_checked == False,  # noqa: E712
            )
        )
        .first()
    )
    if existing:
        if existing.unit is None and unit is not None:
            existing.unit = unit
        if existing.target_qty is None and target_qty is not None:
            existing.target_qty = target_qty
        return existing

    item = ShoppingListItem(
        user_id=user_id,
        ingredient_id=ingredient_id,
        item_text=None,
        target_qty=target_qty,
        unit=unit,
        is_checked=False,
    )
    db.add(item)
    db.flush()
    return item

def set_checked(db: Session, user_id, item_id, is_checked: bool) -> bool:
    item = (
        db.query(ShoppingListItem)
        .filter(and_(ShoppingListItem.user_id == user_id, ShoppingListItem.item_id == item_id))
        .first()
    )
    if not item:
        return False
    item.is_checked = is_checked
    return True

def delete_shopping_item(db: Session, user_id, item_id) -> bool:
    item = (
        db.query(ShoppingListItem)
        .filter(and_(ShoppingListItem.user_id == user_id, ShoppingListItem.item_id == item_id))
        .first()
    )
    if not item:
        return False
    db.delete(item)
    return True

def refresh_shopping_from_pantry(db: Session, user_id):
    pantry_low = (
        db.query(PantryItem)
        .filter(PantryItem.user_id == user_id)
        .filter(
            or_(
                PantryItem.quantity <= 0,
                and_(PantryItem.low_threshold != None, PantryItem.quantity <= PantryItem.low_threshold),  # noqa: E711
            )
        )
        .all()
    )

    processed = 0
    for it in pantry_low:
        ensure_auto_item_exists(
            db,
            user_id=user_id,
            ingredient_id=it.ingredient_id,
            unit=it.unit,
            target_qty=float(it.low_threshold) if it.low_threshold is not None else None,
        )
        processed += 1

    return {"matched": len(pantry_low), "processed": processed}