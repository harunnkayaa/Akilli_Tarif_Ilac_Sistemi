"""Minimal DB connection and ping (psycopg2)."""
import psycopg2
from typing import Optional, Dict, Any
import psycopg2.extras
from uuid import UUID

from .config import (
    DB_HOST,
    DB_PORT,
    DB_USER,
    DB_PASSWORD,
    DB_NAME,
)


def get_conn():
    """Return a new DB connection."""
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        dbname=DB_NAME,
    )


def db_ping() -> bool:
    """Run SELECT 1; return True if ok."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
        return True
    finally:
        conn.close()

def get_user_by_email(email: str) -> Optional[Dict[str, Any]]:
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                "SELECT user_id, email, password_hash, is_active FROM users WHERE email = %s",
                (email,),
            )
            return cur.fetchone()
    finally:
        conn.close()


def create_user(email: str, password_hash: str) -> Dict[str, Any]:
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                """
                INSERT INTO users (email, password_hash)
                VALUES (%s, %s)
                RETURNING user_id, email, is_active, created_at
                """,
                (email, password_hash),
            )
            row = cur.fetchone()
        conn.commit()
        return row
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def get_user_by_id(user_id: str):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT user_id, email, password_hash, is_active
                FROM users
                WHERE user_id = %s
                """,
                (user_id,),
            )
            row = cur.fetchone()
            if not row:
                return None
            return {
                "user_id": row[0],
                "email": row[1],
                "password_hash": row[2],
                "is_active": row[3],
            }
    finally:
        conn.close()