"""
Query embedding (OpenAI).
Vektör boyutu, veritabanındaki rag_documents.embedding kolonuyla uyumlu olacak
şekilde app.core.config.EMBEDDING_DIMENSIONS değerine göre kesilir.
"""
from __future__ import annotations

import logging
from typing import List

from app.core.config import OPENAI_API_KEY, OPENAI_EMBED_MODEL, EMBEDDING_DIMENSIONS

logger = logging.getLogger(__name__)


def embed_query(text: str) -> List[float]:
    text = (text or "").strip()
    if not text:
        return []

    if not OPENAI_API_KEY:
        raise RuntimeError("OPENAI_API_KEY is missing")

    model = OPENAI_EMBED_MODEL or "text-embedding-3-small"

    try:
        # Official OpenAI python client
        from openai import OpenAI
        client = OpenAI(api_key=OPENAI_API_KEY)

        resp = client.embeddings.create(model=model, input=text)
        vec = list(resp.data[0].embedding or [])
        # DB'deki vektör boyutuna (EMBEDDING_DIMENSIONS) göre kes
        if EMBEDDING_DIMENSIONS and len(vec) > EMBEDDING_DIMENSIONS:
            vec = vec[:EMBEDDING_DIMENSIONS]
        return [float(x) for x in vec]
    except Exception as e:
        logger.exception("embed_query failed: %s", e)
        raise