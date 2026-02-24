from __future__ import annotations

from typing import List, Optional, Any, Dict
from uuid import UUID

from sqlalchemy import text, select
from sqlalchemy.orm import Session, joinedload

from app.core.models.user_drug import UserDrug
from app.core.models.user_drug_schedule import UserDrugSchedule
from app.core.models.drug_inventory import DrugInventory
from app.core.schemas.drugs import UserDrugCreate, UserDrugUpdate


def suggest_drug_names(db: Session, q: str, limit: int = 10) -> List[str]:
    q = (q or "").strip()
    if not q:
        return []

    stmt = text("""
        SELECT DISTINCT drug_name
        FROM drug_food_interactions
        WHERE drug_name ILIKE :pat
        ORDER BY drug_name
        LIMIT :limit
    """)
    rows = db.execute(stmt, {"pat": f"{q}%", "limit": limit}).all()
    return [r[0] for r in rows if r and r[0]]


def list_user_drugs(db: Session, user_id: UUID) -> List[UserDrug]:
    q = (
        db.query(UserDrug)
        .options(joinedload(UserDrug.schedules), joinedload(UserDrug.inventory))
        .filter(UserDrug.user_id == user_id)
        .order_by(UserDrug.drug_name.asc())
    )
    return q.all()


def create_user_drug(db: Session, user_id: UUID, payload: UserDrugCreate) -> UserDrug:
    drug = UserDrug(
        user_id=user_id,
        drug_name=payload.drug_name.strip(),
        atc_code=(payload.atc_code.strip() if payload.atc_code else None),
        start_date=payload.start_date,
        end_date=payload.end_date,
        notes=payload.notes,
    )
    db.add(drug)
    db.flush()

    for s in payload.schedules:
        db.add(UserDrugSchedule(
            user_drug_id=drug.user_drug_id,
            time_of_day=s.time_of_day,
            dose_text=s.dose_text,
            days_mask=s.days_mask,
            is_active=s.is_active,
        ))

    if payload.inventory is not None:
        inv = DrugInventory(
            user_drug_id=drug.user_drug_id,
            quantity=payload.inventory.quantity,
            unit=payload.inventory.unit,
            low_threshold=payload.inventory.low_threshold,
        )
        db.add(inv)

    db.commit()
    db.refresh(drug)
    return drug


def update_user_drug(
    db: Session,
    user_id: UUID,
    user_drug_id: UUID,
    payload: UserDrugUpdate
) -> Optional[UserDrug]:
    drug: UserDrug | None = (
        db.query(UserDrug)
        .options(joinedload(UserDrug.schedules), joinedload(UserDrug.inventory))
        .filter(UserDrug.user_drug_id == user_drug_id, UserDrug.user_id == user_id)
        .first()
    )
    if not drug:
        return None

    if payload.drug_name is not None:
        drug.drug_name = payload.drug_name.strip()
    if payload.atc_code is not None:
        drug.atc_code = payload.atc_code.strip() if payload.atc_code else None
    if payload.start_date is not None or payload.start_date is None:
        drug.start_date = payload.start_date
    if payload.end_date is not None or payload.end_date is None:
        drug.end_date = payload.end_date
    if payload.notes is not None or payload.notes is None:
        drug.notes = payload.notes

    if payload.schedules is not None:
        db.query(UserDrugSchedule).filter(UserDrugSchedule.user_drug_id == user_drug_id).delete()
        for s in payload.schedules:
            db.add(UserDrugSchedule(
                user_drug_id=user_drug_id,
                time_of_day=s.time_of_day,
                dose_text=s.dose_text,
                days_mask=s.days_mask,
                is_active=s.is_active,
            ))

    if payload.inventory is not None:
        inv: DrugInventory | None = (
            db.query(DrugInventory).filter(DrugInventory.user_drug_id == user_drug_id).first()
        )
        if inv is None:
            inv = DrugInventory(user_drug_id=user_drug_id)
            db.add(inv)
        inv.quantity = payload.inventory.quantity
        inv.unit = payload.inventory.unit
        inv.low_threshold = payload.inventory.low_threshold

    db.commit()
    db.refresh(drug)
    return drug


def delete_user_drug(db: Session, user_id: UUID, user_drug_id: UUID) -> bool:
    drug = db.query(UserDrug).filter(
        UserDrug.user_drug_id == user_drug_id,
        UserDrug.user_id == user_id
    ).first()
    if not drug:
        return False
    db.delete(drug)
    db.commit()
    return True


def get_interactions_for_drug_name(db: Session, drug_name: str) -> List[Dict[str, Any]]:
    stmt = text("""
        SELECT *
        FROM drug_food_interactions
        WHERE drug_name = :dn
        ORDER BY drug_name
        LIMIT 200
    """)
    res = db.execute(stmt, {"dn": drug_name}).mappings().all()
    return [dict(r) for r in res]