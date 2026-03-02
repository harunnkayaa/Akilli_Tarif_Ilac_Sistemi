"""Son önerilen tarif id'leri (session bazlı). 'Başka öner' için önceki önerileri ele/cezalandırır.
Tablo yoksa: CREATE TABLE recipe_suggestions_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES chat_sessions(session_id) ON DELETE CASCADE,
  recipe_id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
); CREATE INDEX ON recipe_suggestions_log(session_id);"""
import uuid
from sqlalchemy import Column, Text, TIMESTAMP, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func

from app.core.database import Base


class RecipeSuggestionLog(Base):
    __tablename__ = "recipe_suggestions_log"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id = Column(UUID(as_uuid=True), ForeignKey("chat_sessions.session_id", ondelete="CASCADE"), nullable=False, index=True)
    recipe_id = Column(Text, nullable=False)
    created_at = Column(TIMESTAMP(timezone=True), nullable=False, server_default=func.now())
