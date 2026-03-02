"""
Tarif vektör / metin tabanlı retrieval.
rag_documents: source_table='recipes', source_pk=tarif_id.
metadata JSONB: kategori ile soft filter (dish_type eşlemesi).
"""
from __future__ import annotations

from typing import List, Tuple, Optional, Dict, Any

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import RAG_SCHEMA, RAG_TABLE, RAG_TOP_K


def _safe_ident(name: str, *, default: str) -> str:
    """
    SQL identifier whitelist:
    - letters, digits, underscore only
    """
    s = (name or "").strip()
    if not s:
        return default
    if not s.replace("_", "").isalnum():
        return default
    return s


def _rag_table_ref() -> str:
    schema = _safe_ident(RAG_SCHEMA, default="rag")
    table = _safe_ident(RAG_TABLE, default="rag_documents")

    # Always quote identifiers to avoid case/keyword issues.
    if schema != "public":
        return f'"{schema}"."{table}"'
    return f'"{table}"'


def _escape_ilike_pattern(q: str) -> str:
    """ILIKE için % ve _ kaçış (genel metin araması; ESCAPE '#' kullanılacak)."""
    s = (q or "").replace("#", "##").replace("%", "#%").replace("_", "#_")
    return "%" + s + "%"


def _metadata_category_filter_sql(filters: Optional[Dict[str, Any]]) -> tuple:
    """
    metadata->>'kategori' ile include (OR) / exclude (AND).
    PostgreSQL ESCAPE '\\' hatası verdiği için kaçış karakteri olarak '#' kullanıyoruz.
    """
    if not filters:
        return "", {}
    inc = [c for c in (filters.get("include_categories") or []) if c and isinstance(c, str)]
    exc = [c for c in (filters.get("exclude_categories") or []) if c and isinstance(c, str)]
    clauses, params = [], {}
    # ESCAPE '#' ile pattern'da #% = literal %, #_ = literal _, ## = literal #
    escape_sql = " ESCAPE '#'"
    if inc:
        inc_parts = []
        for i, cat in enumerate(inc):
            params[f"inc_{i}"] = _escape_ilike_pattern(cat.strip())
            inc_parts.append(f"(COALESCE(metadata->>'kategori','') ILIKE :inc_{i}{escape_sql})")
        clauses.append("(" + " OR ".join(inc_parts) + ")")
    for i, cat in enumerate(exc):
        params[f"exc_{i}"] = _escape_ilike_pattern(cat.strip())
        clauses.append(f"(COALESCE(metadata->>'kategori','') NOT ILIKE :exc_{i}{escape_sql})")
    if not clauses:
        return "", {}
    return " AND " + " AND ".join(clauses), params


def retrieve_recipe_ids(
    db: Session,
    query_text: str,
    top_k: int = RAG_TOP_K,
    query_embedding: Optional[List[float]] = None,
    filters: Optional[Dict[str, Any]] = None,
) -> List[Tuple[str, float]]:
    """
    Öneri için tarif id'leri ve skorları döner.
    query_embedding verilirse pgvector cosine benzerliği kullanılır;
    verilmezse metin araması (title + content) yapılır.

    Dönüş: [(tarif_id, score), ...]
    """
    q = (query_text or "").strip()
    if not q:
        return []

    table_ref = _rag_table_ref()
    k = int(top_k or RAG_TOP_K or 50)
    if k <= 0:
        k = 50

    meta_sql, meta_params = _metadata_category_filter_sql(filters)

    # --- Vector path ---
    if query_embedding:
        vec_str = "[" + ",".join(f"{float(x):.8f}" for x in query_embedding) + "]"
        sql = text(f"""
            SELECT source_pk AS tarif_id,
                   1 - (embedding <=> CAST(:vec AS vector)) AS score
            FROM {table_ref}
            WHERE source_table = 'recipes'
              AND embedding IS NOT NULL
              {meta_sql}
            ORDER BY embedding <=> CAST(:vec AS vector)
            LIMIT :top_k
        """)
        params = {"vec": vec_str, "top_k": k, **meta_params}
        try:
            rows = db.execute(sql, params).fetchall()
        except Exception:
            # metadata kolonu yoksa filtresiz dene
            if meta_sql:
                sql = text(f"""
                    SELECT source_pk AS tarif_id,
                           1 - (embedding <=> CAST(:vec AS vector)) AS score
                    FROM {table_ref}
                    WHERE source_table = 'recipes' AND embedding IS NOT NULL
                    ORDER BY embedding <=> CAST(:vec AS vector)
                    LIMIT :top_k
                """)
                rows = db.execute(sql, {"vec": vec_str, "top_k": k}).fetchall()
            else:
                raise
        return [(str(r[0]), float(r[1])) for r in rows if r and r[0]]

    # --- Text fallback ---
    pattern = _escape_ilike_pattern(q)
    escape_sql = " ESCAPE '#'"
    sql = text(f"""
        SELECT source_pk AS tarif_id, 1.0 AS score
        FROM {table_ref}
        WHERE source_table = 'recipes'
          AND (title ILIKE :pat{escape_sql} OR content ILIKE :pat{escape_sql})
          {meta_sql}
        LIMIT :top_k
    """)
    params = {"pat": pattern, "top_k": k, **meta_params}
    try:
        rows = db.execute(sql, params).fetchall()
    except Exception:
        if meta_sql:
            sql = text(f"""
                SELECT source_pk AS tarif_id, 1.0 AS score
                FROM {table_ref}
                WHERE source_table = 'recipes'
                  AND (title ILIKE :pat{escape_sql} OR content ILIKE :pat{escape_sql})
                LIMIT :top_k
            """)
            rows = db.execute(sql, {"pat": pattern, "top_k": k}).fetchall()
        else:
            raise
    if rows:
        return [(str(r[0]), float(r[1])) for r in rows if r and r[0]]
    words = [w.strip() for w in q.split() if len(w.strip()) >= 2]
    if not words:
        return []
    conditions = " OR ".join(
        f"(title ILIKE :w{i} OR content ILIKE :w{i})" for i in range(len(words)))
    params = {"top_k": k, **meta_params}
    for i, w in enumerate(words):
        params[f"w{i}"] = "%" + w.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
    sql = text(f"""
        SELECT DISTINCT source_pk AS tarif_id, 1.0 AS score
        FROM {table_ref}
        WHERE source_table = 'recipes' AND ({conditions})
        {meta_sql}
        LIMIT :top_k
    """)
    try:
        rows = db.execute(sql, params).fetchall()
    except Exception:
        if meta_sql:
            params_no_meta = {"top_k": k}
            for i, w in enumerate(words):
                params_no_meta[f"w{i}"] = "%" + w.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
            sql = text(f"""
                SELECT DISTINCT source_pk AS tarif_id, 1.0 AS score
                FROM {table_ref}
                WHERE source_table = 'recipes' AND ({conditions})
                LIMIT :top_k
            """)
            rows = db.execute(sql, params_no_meta).fetchall()
        else:
            raise
    return [(str(r[0]), float(r[1])) for r in rows if r and r[0]]