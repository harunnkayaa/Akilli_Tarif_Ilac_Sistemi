# backend/app/core/crud/kitchen.py  (MODE=ADD + STOCK ARTTIYSA SHOPPING'TEN DÜŞÜR)
from typing import List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from app.core.models.pantry_items import PantryItem
from app.core.models.shopping_list_items import ShoppingListItem


def _norm_shopping_name(name: Optional[str]) -> str:
    return (name or "").strip().casefold()


def _find_unchecked_shopping(db: Session, user_id, name: str) -> Optional[ShoppingListItem]:
    """Aynı ürün adı ingredient_id veya item_text ile kayıtlıysa tek satır bul."""
    key = _norm_shopping_name(name)
    if not key:
        return None
    rows = (
        db.query(ShoppingListItem)
        .filter(
            ShoppingListItem.user_id == user_id,
            ShoppingListItem.is_checked == False,  # noqa: E712
        )
        .all()
    )
    for row in rows:
        for field in (row.ingredient_id, row.item_text):
            if field and _norm_shopping_name(field) == key:
                return row
    return None


def dedupe_shopping_list(db: Session, user_id) -> int:
    """Aynı isimli işaretlenmemiş satırları birleştir; fazlaları sil."""
    rows = (
        db.query(ShoppingListItem)
        .filter(
            ShoppingListItem.user_id == user_id,
            ShoppingListItem.is_checked == False,  # noqa: E712
        )
        .all()
    )
    groups: dict[str, list] = {}
    for row in rows:
        label = row.ingredient_id or row.item_text
        key = _norm_shopping_name(label)
        if not key:
            continue
        groups.setdefault(key, []).append(row)

    removed = 0
    for group in groups.values():
        if len(group) <= 1:
            continue
        # ingredient_id dolu olanı tercih et, sonra en eski
        group.sort(key=lambda r: (0 if r.ingredient_id else 1, r.created_at))
        keeper = group[0]
        if keeper.ingredient_id is None and keeper.item_text:
            # stok kaydı varsa ingredient_id'ye bağla
            pantry = (
                db.query(PantryItem)
                .filter(
                    PantryItem.user_id == user_id,
                    PantryItem.ingredient_id == keeper.item_text,
                )
                .first()
            )
            if pantry:
                keeper.ingredient_id = pantry.ingredient_id
                keeper.item_text = None
        for dup in group[1:]:
            if dup.target_qty is not None:
                keeper.target_qty = float(keeper.target_qty or 0) + float(dup.target_qty)
            if keeper.unit is None and dup.unit is not None:
                keeper.unit = dup.unit
            db.delete(dup)
            removed += 1
    if removed:
        db.flush()
    return removed


def list_pantry(db: Session, user_id) -> List[PantryItem]:
    return (
        db.query(PantryItem)
        .filter(PantryItem.user_id == user_id)
        .order_by(PantryItem.ingredient_id.asc())
        .all()
    )

def _delete_auto_shopping_if_exists(db: Session, user_id, ingredient_id: str):
    # Aynı isimli tüm işaretlenmemiş satırları sil (ingredient_id veya item_text)
    key = _norm_shopping_name(ingredient_id)
    rows = (
        db.query(ShoppingListItem)
        .filter(
            ShoppingListItem.user_id == user_id,
            ShoppingListItem.is_checked == False,  # noqa: E712
        )
        .all()
    )
    for it in rows:
        for field in (it.ingredient_id, it.item_text):
            if field and _norm_shopping_name(field) == key:
                db.delete(it)
                break

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

def pantry_quantity_map(db: Session, user_id) -> dict:
    rows = db.query(PantryItem).filter(PantryItem.user_id == user_id).all()
    return {r.ingredient_id: float(r.quantity or 0) for r in rows}

def list_shopping(db: Session, user_id) -> List[ShoppingListItem]:
    return (
        db.query(ShoppingListItem)
        .filter(ShoppingListItem.user_id == user_id)
        .order_by(ShoppingListItem.created_at.asc())
        .all()
    )

def add_manual_shopping_item(db: Session, user_id, item_text: str, target_qty: Optional[float], unit: Optional[str]):
    existing = _find_unchecked_shopping(db, user_id, item_text)
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
    existing = _find_unchecked_shopping(db, user_id, ingredient_id)
    if existing:
        existing.ingredient_id = ingredient_id
        existing.item_text = None
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
    db.flush()
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

    deduped = dedupe_shopping_list(db, user_id)
    return {"matched": len(pantry_low), "processed": processed, "deduped": deduped}