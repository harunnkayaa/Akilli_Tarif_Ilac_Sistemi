from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple
from uuid import UUID

from sqlalchemy.orm import Session, joinedload

from app.core.models.user_drug import UserDrug
from app.core.models.drug_inventory import DrugInventory
from app.core.models.drug_intake_event import DrugIntakeEvent
from app.core.models.drug_snooze_plan import DrugSnoozePlan


def _dose_from_schedule(drug: UserDrug, scheduled_at: Optional[datetime]) -> int:
    """
    dose_text artık sayı string (örn "1").
    scheduled_at time_of_day ile eşleştirip dozu bulur.
    """
    if scheduled_at is None or not getattr(drug, "schedules", None):
        return 1

    if scheduled_at.tzinfo is None:
        scheduled_at = scheduled_at.replace(tzinfo=timezone.utc)

    target_time = scheduled_at.timetz().replace(tzinfo=None)

    for s in drug.schedules:
        try:
            if s.time_of_day.hour == target_time.hour and s.time_of_day.minute == target_time.minute:
                dt = (s.dose_text or "").strip()
                n = int(dt) if dt.isdigit() else 1
                return max(1, n)
        except Exception:
            continue

    return 1


def apply_intake(
    db: Session,
    user_id: UUID,
    user_drug_id: UUID,
    client_event_id: str,
    action: str,  # TAKEN / SNOOZE / SKIP / MISSED
    scheduled_at: Optional[datetime],
    snooze_minutes: int,
) -> Tuple[bool, Optional[int], Optional[datetime], str, bool]:
    """
    Returns: (idempotent, new_quantity, remind_at, resolved_action)
    """

    action = (action or "").upper().strip()
    if action not in ("TAKEN", "SNOOZE", "SKIP", "MISSED"):
        raise ValueError("Invalid action")

    # Mobil tarafta otomatik kaçırılan ilaç MISSED gelebilir.
    # Veritabanında MISSED action yok, bu durum sistemde SKIP gibi tutulur.
    if action == "MISSED":
        action = "SKIP"

    # 1) idempotency check (same occurrence)
    existing = (
        db.query(DrugIntakeEvent)
        .filter(
            DrugIntakeEvent.user_id == user_id,
            DrugIntakeEvent.client_event_id == client_event_id,
        )
        .first()
    )
    if existing:
        if action == "SKIP" and existing.action == "SNOOZE":
            now = datetime.now(timezone.utc)
            sp = (
                db.query(DrugSnoozePlan)
                .filter(
                    DrugSnoozePlan.intake_event_id == existing.intake_event_id,
                    DrugSnoozePlan.is_active == True,
                )
                .order_by(DrugSnoozePlan.created_at.desc())
                .first()
            )
            remind_at_snooze = sp.remind_at if sp else None
            grace = timedelta(minutes=max(1, int(snooze_minutes or 5)) + 1)
            if remind_at_snooze and now >= remind_at_snooze + grace:
                existing.action = "SKIP"
                db.query(DrugSnoozePlan).filter(
                    DrugSnoozePlan.intake_event_id == existing.intake_event_id,
                    DrugSnoozePlan.is_active == True,
                ).update({"is_active": False})
                db.commit()
                return True, None, None, "SKIP", False

        # Tekrar Ertele: aynı doz için remind_at güncellenir (+5 dk)
        if action == "SNOOZE" and existing.action == "SNOOZE":
            now = datetime.now(timezone.utc)
            remind_at = now + timedelta(minutes=max(1, int(snooze_minutes or 5)))
            db.query(DrugSnoozePlan).filter(
                DrugSnoozePlan.intake_event_id == existing.intake_event_id,
                DrugSnoozePlan.is_active == True,
            ).update({"is_active": False})
            db.add(
                DrugSnoozePlan(
                    intake_event_id=existing.intake_event_id,
                    remind_at=remind_at,
                    is_active=True,
                )
            )
            db.commit()
            return True, None, remind_at, "SNOOZE", False

        remind_at = None
        if existing.action == "SNOOZE":
            sp = (
                db.query(DrugSnoozePlan)
                .filter(
                    DrugSnoozePlan.intake_event_id == existing.intake_event_id,
                    DrugSnoozePlan.is_active == True,
                )
                .order_by(DrugSnoozePlan.created_at.desc())
                .first()
            )
            remind_at = sp.remind_at if sp else None

        new_qty = None
        depleted = False
        if existing.action == "TAKEN":
            inv = db.query(DrugInventory).filter(DrugInventory.user_drug_id == user_drug_id).first()
            if inv is not None:
                new_qty = inv.quantity
                depleted = (inv.quantity or 0) <= 0

        return True, new_qty, remind_at, existing.action, depleted

    # 2) ownership + load schedules/inventory
    drug: UserDrug | None = (
        db.query(UserDrug)
        .options(joinedload(UserDrug.schedules), joinedload(UserDrug.inventory))
        .filter(UserDrug.user_drug_id == user_drug_id, UserDrug.user_id == user_id)
        .first()
    )
    if not drug:
        raise ValueError("Drug not found")

    # 3) dose MUST be set BEFORE flush (DB NOT NULL)
    dose = 1
    if action == "TAKEN":
        dose = _dose_from_schedule(drug, scheduled_at)

    # 4) create event (dose always int, never None)
    ev = DrugIntakeEvent(
        user_id=user_id,
        user_drug_id=user_drug_id,
        client_event_id=client_event_id,
        action=action,
        scheduled_at=scheduled_at,
        dose=dose,
    )
    db.add(ev)
    db.flush()  # intake_event_id gelsin

    remind_at: Optional[datetime] = None
    new_qty: Optional[int] = None
    stock_depleted = False

    if action == "TAKEN":
        inv = drug.inventory
        if inv is None:
            new_qty = None
        else:
            inv.quantity = max(0, (inv.quantity or 0) - dose)
            new_qty = inv.quantity
            if new_qty <= 0:
                stock_depleted = True
                for sched in drug.schedules or []:
                    sched.is_active = False

    elif action == "SKIP":
        # stok düşmez
        pass

    elif action == "SNOOZE":
        # backend snooze plan kaydı
        now = datetime.now(timezone.utc)
        remind_at = now + timedelta(minutes=max(1, int(snooze_minutes or 5)))

        # aynı event için önceki aktif planları pasifleştir (temiz iş)
        db.query(DrugSnoozePlan).filter(
            DrugSnoozePlan.intake_event_id == ev.intake_event_id,
            DrugSnoozePlan.is_active == True,
        ).update({"is_active": False})

        db.add(
            DrugSnoozePlan(
                intake_event_id=ev.intake_event_id,
                remind_at=remind_at,
                is_active=True,
            )
        )

    db.commit()
    return False, new_qty, remind_at, action, stock_depleted