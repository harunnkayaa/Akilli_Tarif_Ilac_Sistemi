from __future__ import annotations

from typing import List, Dict, Any
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.schemas.drugs import UserDrugCreate, UserDrugUpdate, UserDrugOut, InteractionRow
from app.core.crud import drugs as crud

# Burayı projendeki auth dependency'ye göre düzelt:
# Çoğu projede: from app.api.deps import get_current_user
# ve current_user.user_id kullanılır.
from app.api.deps import get_current_user

router = APIRouter(prefix="/drugs", tags=["drugs"])


@router.get("/suggest", response_model=List[str])
def suggest(q: str = Query(..., min_length=1), db: Session = Depends(get_db)):
    return crud.suggest_drug_names(db, q=q, limit=10)


@router.get("", response_model=List[UserDrugOut])
def list_my_drugs(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    drugs = crud.list_user_drugs(db, user_id=current_user.user_id)

    out: List[UserDrugOut] = []
    for d in drugs:
        active_count = sum(1 for s in (d.schedules or []) if s.is_active)
        low_stock = False
        if d.inventory is not None:
            low_stock = d.inventory.quantity <= d.inventory.low_threshold

        item = UserDrugOut.model_validate(d)  # pydantic v2
        item.schedule_count_active = active_count
        item.low_stock = low_stock
        out.append(item)

    return out


@router.post("", response_model=UserDrugOut, status_code=201)
def create_drug(
    payload: UserDrugCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    drug = crud.create_user_drug(db, user_id=current_user.user_id, payload=payload)

    active_count = sum(1 for s in (drug.schedules or []) if s.is_active)
    low_stock = False
    if drug.inventory is not None:
        low_stock = drug.inventory.quantity <= drug.inventory.low_threshold

    item = UserDrugOut.model_validate(drug)
    item.schedule_count_active = active_count
    item.low_stock = low_stock
    return item


@router.put("/{user_drug_id}", response_model=UserDrugOut)
def update_drug(
    user_drug_id: UUID,
    payload: UserDrugUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    drug = crud.update_user_drug(
        db,
        user_id=current_user.user_id,
        user_drug_id=user_drug_id,
        payload=payload,
    )
    if not drug:
        raise HTTPException(status_code=404, detail="Drug not found")

    active_count = sum(1 for s in (drug.schedules or []) if s.is_active)
    low_stock = False
    if drug.inventory is not None:
        low_stock = drug.inventory.quantity <= drug.inventory.low_threshold

    item = UserDrugOut.model_validate(drug)
    item.schedule_count_active = active_count
    item.low_stock = low_stock
    return item


@router.delete("/{user_drug_id}", status_code=204)
def delete_drug(
    user_drug_id: UUID,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    ok = crud.delete_user_drug(db, user_id=current_user.user_id, user_drug_id=user_drug_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Drug not found")
    return


@router.get("/{user_drug_id}/interactions", response_model=List[InteractionRow])
def interactions(
    user_drug_id: UUID,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    # önce bu ilaç current_user'a mı ait kontrolü listeden yapıyoruz (kolay MVP)
    drugs = crud.list_user_drugs(db, user_id=current_user.user_id)
    target = next((d for d in drugs if d.user_drug_id == user_drug_id), None)
    if not target:
        raise HTTPException(status_code=404, detail="Drug not found")

    return crud.get_interactions_for_drug_name(db, drug_name=target.drug_name)