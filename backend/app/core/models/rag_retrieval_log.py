from sqlalchemy import Column, Text, Integer, TIMESTAMP, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.sql import func

from app.core.database import Base


class RagRetrievalLog(Base):
    __tablename__ = "rag_retrieval_log"

    retrieval_id = Column(UUID(as_uuid=True), primary_key=True)
    message_id = Column(UUID(as_uuid=True), ForeignKey("chat_messages.message_id", ondelete="CASCADE"), nullable=False, index=True)
    query_text = Column(Text, nullable=False)
    retrieved_sources = Column(JSONB, nullable=False)
    top_k = Column(Integer, nullable=False)
    created_at = Column(TIMESTAMP(timezone=True), nullable=False, server_default=func.now())
