"""
Sorgu embedding üretimi — RAG retrieval için.
OpenAI text-embedding-3-small, 768 boyut; rag_documents ile aynı kurulum.
LangChain kullanılmaz.
"""
from __future__ import annotations

import logging
from typing import List, Optional

from app.core.config import OPENAI_API_KEY, OPENAI_EMBEDDING_MODEL, EMBEDDING_DIMENSIONS

logger = logging.getLogger(__name__)


def embed_query(text: str) -> Optional[List[float]]:
    """
    Metni vektörleştirir. Rag_documents ile aynı model/boyut kullanılmalı.
    model: text-embedding-3-small, dimensions: 768.
    Hata veya eksik API key durumunda None döner ve ILIKE fallback kullanılır.
    """
    if not (text or "").strip():
        return None
    if not OPENAI_API_KEY:
        logger.warning("OPENAI_API_KEY not set; skipping embedding, using ILIKE fallback")
        return None
    try:
        from openai import OpenAI
        client = OpenAI(api_key=OPENAI_API_KEY)
        resp = client.embeddings.create(
            model=OPENAI_EMBEDDING_MODEL,
            input=[text.strip()],
            dimensions=EMBEDDING_DIMENSIONS,
        )
        if not resp.data or len(resp.data) == 0:
            logger.warning("OpenAI embeddings returned no data; using ILIKE fallback")
            return None
        vec = resp.data[0].embedding
        if len(vec) != EMBEDDING_DIMENSIONS:
            logger.warning(
                "OpenAI embedding length %s != %s; using ILIKE fallback",
                len(vec),
                EMBEDDING_DIMENSIONS,
            )
            return None
        return vec
    except Exception as e:
        logger.exception("Embedding failed (%s); using ILIKE fallback", e)
        return None
