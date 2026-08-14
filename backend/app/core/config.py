"""DB settings from env with defaults. .env dosyası backend/ klasöründen yüklenir."""
import os
from pathlib import Path

# Backend kökünde .env varsa yükle (uvicorn hangi dizinden çalışırsa çalışsın)
_backend_root = Path(__file__).resolve().parent.parent.parent
_env_path = _backend_root / ".env"
if _env_path.exists():
    from dotenv import load_dotenv
    # .env değerleri mevcut ortam değişkenlerini override etsin (özellikle BASE_URL vb.)
    load_dotenv(_env_path, override=True)

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_USER = os.getenv("DB_USER", "appuser")
DB_PASSWORD = os.getenv("DB_PASSWORD", "apppass")
DB_NAME = os.getenv("DB_NAME", "smartapp")

SECRET_KEY = os.getenv("SECRET_KEY", "dev-secret-change-me")
ALGORITHM = os.getenv("ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "60"))

# RAG: rag_documents tablosunun şeması (tablo: rag.rag_documents)
RAG_SCHEMA = os.getenv("RAG_SCHEMA", "").strip() or "rag"
RAG_TABLE = "rag_documents"
RAG_TOP_K = int(os.getenv("RAG_TOP_K", "300"))
# Tarif öneri pipeline (talimat)
RAG_CANDIDATE_K = int(os.getenv("RAG_CANDIDATE_K", "150"))  # retrieval aday sayısı
LLM_RERANK_K = int(os.getenv("LLM_RERANK_K", "40"))         # LLM rerank sonrası seçilecek sayı
CHAT_HISTORY_N = int(os.getenv("CHAT_HISTORY_N", "8"))      # chat hafıza mesaj sayısı

# OpenAI: query embedding (must match rag_documents embedding setup)
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "").strip()
OPENAI_EMBEDDING_MODEL = os.getenv("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")
# Eski isimle import eden kodlar için geriye dönük alias
OPENAI_EMBED_MODEL = OPENAI_EMBEDDING_MODEL
EMBEDDING_DIMENSIONS = int(os.getenv("EMBEDDING_DIMENSIONS", "768"))

# Geçici debug: /recipes/chat/suggest kartlarına skor alanları ekler
DEBUG_RECIPE_SCORING = os.getenv("DEBUG_RECIPE_SCORING", "").strip() == "1"
# Hangi cevapların LLM'den geldiğini logla + yanıtta llm_sources döndür (intent, general_chat, rerank, polish)
DEBUG_LLM_SOURCES = os.getenv("DEBUG_LLM_SOURCES", "").strip() == "1"

# Tarif sohbeti: LLM (LangChain ChatOpenAI) ile assistant_text + kart reason
USE_RECIPE_LLM = os.getenv("USE_RECIPE_LLM", "").strip() == "1"
# GPT modeli (LangChain ile kullanılır). .env: OPENAI_CHAT_MODEL=gpt-4o-mini
OPENAI_CHAT_MODEL = os.getenv("OPENAI_CHAT_MODEL", "").strip() or "gpt-4o-mini"

# API temel adresi (örn. http://localhost:8000). Sonunda / olmamalı.
BASE_URL = os.getenv("BASE_URL", "http://localhost:8000").rstrip("/")
