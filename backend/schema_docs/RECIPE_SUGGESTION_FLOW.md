# Tarif Öneri Sistemi — Akış Özeti

Bu dokümanda `POST /recipes/chat/suggest` ile tetiklenen **tarif öneri akışı** adım adım özetleniyor. Kod: `chat_service.suggest_recipes`, `intent_service`, `retrieval_service`, `embedding_service`, `rules_engine`, `llm_service`.

---

## 1. Giriş

- **Girdi:** `user_id`, `message`, isteğe bağlı `session_id`.
- **Çıkış:** `{ session_id, assistant_text, cards }`.

---

## 2. Oturum ve mesaj kaydı

1. **Session:** `get_or_create_session(db, user_id, session_id)` → `session_uuid`.
2. **Kullanıcı mesajı** `chat_messages` tablosuna yazılır (`role=user`), `db.commit()`.

---

## 3. Niyet çıkarımı (Intent)

- **Kaynak:** `intent_service.extract_intent(message, chat_history, last_cards)`.
- **chat_history:** Son 8 mesaj `_get_last_n_messages(db, session_uuid)`.
- **last_cards:** Son 10 önerilen tarif id’si `_get_last_suggested_recipe_ids(db, session_uuid, 10)` (tablo: `recipe_suggestions_log`).
- **LLM:** LangChain + ChatPromptTemplate + MessagesPlaceholder (chat_history). Çıktı: `IntentResult` (Pydantic).
- **IntentResult alanları:**  
  `intent` (recipe_request | general_chat), `dish_type`, `include_ingredients`, `exclude_categories`, `include_categories`, `rewrite_query`, `wants_alternatives`, `wants_cards`.
- LLM kapalı/hata: Deterministic fallback (tarif ipuçlu mesajlar → recipe_request, sadece selam/teşekkür → general_chat).

---

## 4. Dal: general_chat

- **Koşul:** `intent_result.intent == "general_chat"`.
- **Yapılan:** LLM ile genel sohbet cevabı (varsa) `generate_general_chat_response(message, chat_history)`; yoksa hazır karşılama metni.
- Asistan mesajı `chat_messages`’a yazılır, **cards = []** ile dönülür. Akış biter.

---

## 5. Dal: recipe_request — Retrieval

- **Sorgu metni (base_q):**  
  `base_q = (intent_result.rewrite_query or message).strip()`  
  + varsa `include_ingredients` birleştirilir. Kategori metne eklenmez (kategori sonradan skorlama/filtrede kullanılır).
- **Embedding:**  
  `query_embedding = embed_query(base_q)` → `embedding_service.embed_query` (OpenAI text-embedding-3-small, 768 dim).  
  Hata/API yoksa `query_embedding=None` → retrieval metin (ILIKE) fallback.
- **Mesaj retrieval:**  
  `retrieve_recipe_ids(db, base_q, top_k=60, query_embedding=query_embedding)`  
  - Kaynak: `rag.rag_documents` (source_table='recipes').  
  - Vektör varsa: cosine distance (pgvector `<=>`), skor = 1 - distance.  
  - Vektör yoksa: title/content ILIKE veya kelime bazlı OR.  
  - Dönüş: `[(tarif_id, score), ...]` (en fazla 60).
- **Kiler retrieval:**  
  `pantry_query = _get_pantry_query_text(db, user_id)` (non-staple malzemeler, en fazla 6).  
  Varsa `embed_query(pantry_query)` ile aynı retrieval → en fazla 50 tarif.
- **Skor birleştirme:**  
  `candidate_scores[recipe_id] = (msg_score, pantry_score)`; her iki retrieval’dan gelen skorlar merge edilir.
- **Log:** `RagRetrievalLog` ile bu turdaki retrieval kaydedilir.

---

## 6. Tarif detayı ve sert filtreler

- **Aday ID’ler:** `all_candidate_ids = list(candidate_scores.keys())`.
- **Detay:** `_fetch_recipes_by_ids(db, all_candidate_ids)` → `recipes` tablosundan tarif_adi, kategori, malzemeler_json vb.
- **Sert filtreler (HARD):**
  - **Alerji:** `has_allergy_match(db, user_id, malzemeler_json)` → eşleşen tarifler çıkarılır.
  - **include_ingredients:** `_recipe_contains_any_ingredient(rec, inc_ings)` → en az bir malzeme tarifte/başlıkta yoksa çıkarılır.
  - **exclude_categories:** `intent_result.exclude_categories` içindeki kategori tarifte geçiyorsa çıkarılır.
- **“Başka öner”:** `wants_alternatives` ise `_get_last_suggested_recipe_ids(db, session_uuid)` ile daha önce önerilenler listeden **tamamen çıkarılır** (HARD EXCLUDE).

Kalan liste: `filtered` (recipe_id’ler).

---

## 7. Skorlama (scored)

- **dish_hint:** `intent_result.dish_type` (skorlama ve kategori uyumu için).
- Her `rid` in `filtered` için:
  - **msg_score, pantry_score:** `candidate_scores[rid]`.
  - **stock_match_score:** `check_recipe_stock(db, user_id, malzemeler_json)` (kiler eşleşmesi).
  - **disliked_penalty:** `disliked_penalty_score(db, user_id, malzemeler_json)`.
  - **cat_score:** `_category_alignment_score(dish_hint, kategori)` (tatlı/çorba/meze vb. uyumu).
  - **final_score** =  
    `WEIGHT_MSG * msg_score + WEIGHT_PANTRY * pantry_score + WEIGHT_STOCK * stock_match_score + WEIGHT_CATEGORY * cat_score - disliked`.
- **Uyarılar (warnings):**  
  `drug_interaction_warnings`, `disease_limit_warnings`, sevilmeyen malzeme, eksik stok metni; kartlara taşınır.
- **Sıralama:** `scored.sort(key=lambda x: -x["score"])`.
- **Üst dilim:** `top = scored[:top_n]` (varsayılan top_n=5) → kullanıcıya gösterilecek **kartlar**.

---

## 8. Kartların oluşturulması

- `top` içinden her öğe için bir **card** dict: recipe_id, title, image_url, reason (başta "—"), warnings, badges (kategori), missing_ingredients, available_ingredients.
- `cards` = kullanıcıya dönecek liste (genelde 5).

---

## 9. LLM Polisher (isteğe bağlı)

- **Koşul:** Kart var, `USE_RECIPE_LLM` ve `OPENAI_API_KEY` set.
- **LLM’e verilen adaylar:** Skorlanmış listeden ilk **15** tarif: `top_for_llm = scored[:TOP_LLM_CANDIDATES]` → `candidates_llm` (recipe_id, title, category, badges, warnings, rank, stock özeti).
- **Gösterilecek kartlar:** Sadece `cards` (5 adet) → `cards_to_show_recipe_ids`.
- **Diğer bağlam:** user_context (diseases, drugs, allergies, disliked), stock_summary_llm, intent (IntentResult.model_dump()).
- **Çağrı:** `generate_assistant_response(user_message, intent, user_context_llm, stock_summary_llm, candidates_llm, cards_to_show_recipe_ids, chat_history)`.
- **LLM çıktısı:**  
  `assistant_text`, `card_reasons` (sadece `cards_to_show_recipe_ids` içindeki tarifler için), `warnings_rewritten` (aynı id’ler için).
- **Kart güncellemesi:** LLM’den gelen reason ve warnings_rewritten, ilgili kartlara yazılır. `assistant_text` varsa genel metin olarak kullanılır.
- LLM yoksa/hata: Varsayılan `assistant_text` (wants_alternatives / dish_type / inc_ings’e göre hazır cümle).

---

## 10. Çıkış ve kalıcılık

- **“Başka öner” hafızası:** Bu turda dönen kartların recipe_id’leri `_log_suggested_recipes(db, session_uuid, recipe_ids)` ile `recipe_suggestions_log` tablosuna yazılır (sonraki “başka öner”de exclude edilir).
- Asistan metni `chat_messages`’a yazılır (`role=assistant`), `db.commit()`.
- **Dönüş:** `{ "session_id": str(session_uuid), "assistant_text": ..., "cards": [...] }`.

---

## Özet blok diyagramı

```
[Kullanıcı mesajı]
       │
       ▼
[Session + mesaj DB'ye yaz]
       │
       ▼
[Intent: extract_intent(message, chat_history, last_cards)]
       │
       ├── general_chat ──► [LLM/hazır cevap] ──► cards=[], return
       │
       └── recipe_request
              │
              ▼
       [base_q = rewrite_query + include_ingredients]
              │
              ▼
       [embed_query(base_q)] ──► [retrieve_recipe_ids (msg)]   top_k=60
       [embed_query(pantry)] ──► [retrieve_recipe_ids (pantry)] top_k=50
              │
              ▼
       [Merge scores → candidate_scores]
              │
              ▼
       [_fetch_recipes_by_ids] → recipe_map
              │
              ▼
       [HARD: allergy, include_ingredients, exclude_categories, wants_alternatives]
              │
              ▼
       [Skorlama: msg + pantry + stock + category - disliked] → scored
              │
              ▼
       [top = scored[:5]] → cards
              │
              ▼
       [LLM Polisher: 15 aday, 5 kart için reason/warnings] → assistant_text + card.reason
              │
              ▼
       [_log_suggested_recipes] → [Assistant mesajı DB] → return { session_id, assistant_text, cards }
```

---

## Dosya / modül eşlemesi

| Adım | Modül / fonksiyon |
|------|-------------------|
| Session, mesaj kayıt | `chat_service`: get_or_create_session, ChatMessage add/commit |
| Intent | `intent_service`: extract_intent (LangChain + IntentResult) |
| General chat | `llm_service`: generate_general_chat_response |
| Embedding | `embedding_service`: embed_query (OpenAI text-embedding-3-small) |
| Retrieval | `retrieval_service`: retrieve_recipe_ids (rag_documents, vector/ILIKE) |
| Alerji / sevilmeyen / stok / ilaç / hastalık | `rules_engine`: has_allergy_match, disliked_penalty_score, check_recipe_stock, drug_interaction_warnings, disease_limit_warnings |
| Skorlama / kart | `chat_service`: candidate_scores merge, filtered, scored, top, cards |
| Polisher | `llm_service`: generate_assistant_response (candidates_llm, cards_to_show_recipe_ids) |
| Başka öner hafızası | `chat_service`: _get_last_suggested_recipe_ids, _log_suggested_recipes, RecipeSuggestionLog |

Bu akış, mevcut kodla uyumlu tarif öneri sisteminin tam resmini verir.
