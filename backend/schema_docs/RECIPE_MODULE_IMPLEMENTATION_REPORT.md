# Tarif Chat + Öneri Modülü — Uygulama Raporu

## Oluşturulan Dosyalar

### Modeller
- `app/core/models/chat_session.py` — chat_sessions
- `app/core/models/chat_message.py` — chat_messages  
- `app/core/models/rag_retrieval_log.py` — rag_retrieval_log
- `app/core/models/meal_log.py` — meal_log
- `app/core/models/daily_nutrient_total.py` — daily_nutrient_totals

### Servisler
- `app/core/services/retrieval_service.py` — RAG vektör/metin retrieval (rag_documents)
- `app/core/services/rules_engine.py` — Alerji (blok), sevilmeyen (ceza), ilaç–gıda, hastalık limiti, stok
- `app/core/services/chat_service.py` — suggest akışı: session, message, retrieval, kurallar, sıralama
- `app/core/services/cook_service.py` — stok kontrolü, düşüm, meal_log, daily_nutrient_totals
- `app/core/services/llm_service.py` — LLM stub (LangChain entegrasyonu için)

### Şemalar
- `app/core/schemas/recipe_chat.py` — RecipeChatSuggestRequest/Response, RecipeCardOut, CookRecipeResponse

### Rota
- `app/api/routes/recipes.py` — POST `/recipes/chat/suggest`, POST `/recipes/{recipe_id}/cook`

---

## Yeni Endpoint'ler

| Method | Path | Açıklama |
|--------|------|----------|
| POST | `/recipes/chat/suggest` | Sohbet mesajına göre tarif önerisi (LLM olmadan) |
| POST | `/recipes/{recipe_id}/cook` | Tarifi pişir: stok düşümü, meal_log, günlük besin güncellemesi |

---

## Kullanılan SQL Sorguları

1. **retrieval_service**
   - Vektör: `SELECT source_pk, 1 - (embedding <=> :vec::vector) FROM rag_documents WHERE source_table = 'recipes' ORDER BY embedding <=> :vec LIMIT :top_k`
   - Metin: `SELECT source_pk FROM rag_documents WHERE source_table = 'recipes' AND (title ILIKE :pat OR content ILIKE :pat) LIMIT :top_k`

2. **chat_service**
   - Tarifler: `SELECT tarif_id, tarif_adi, ... FROM recipes WHERE tarif_id IN (...)`

3. **cook_service**
   - Tarif: `SELECT tarif_id, tarif_adi, porsiyon_sayisi, toplam_kalori_kcal, malzemeler_json FROM recipes WHERE tarif_id = :tid`

4. **rules_engine**
   - İlaç–gıda: `SELECT food_name_tr, recommendation_tr, interaction_effect FROM drug_food_interactions WHERE drug_name = :dn`

---

## Kural Motoru (Kurallar ve Skorlama)

- **Alerji**: `user_allergies.raw_text` (token) × `malzemeler_json[].Malzeme_Adi` (token) → eşleşme varsa tarif **tamamen elenir** (HARD BLOCK).
- **Sevilmeyen**: Aynı token eşleştirme; eşleşen her malzeme için **skor cezası +0.2** (SOFT).
- **İlaç–gıda**: `user_drugs` + `drug_food_interactions.food_name_tr` tarif malzemesiyle eşleşirse **uyarı** eklenir.
- **Hastalık limiti**: `user_diseases` + `disease_nutrient_limits` (energy_kcal) + `daily_nutrient_totals`; aşım varsa DSÖ uyarı metni eklenir.
- **Stok**: `check_recipe_stock`: Malzeme_Adi → ingredients (canonical_name_tr / token) → pantry_items; yetersizse uyarı (suggest) veya cook’ta hata.

Sıralama: retrieval skoru − sevilmeyen cezası; en yüksekten itibaren top 5.

---

## Stok Düşüm Mantığı

- `cook_recipe`: Önce `check_recipe_stock` ile gerekli miktarlar ve pantry eşleşmeleri alınır.
- Eksik varsa `success=False`, `missing` listesi döner; **hiçbir stok düşülmez**.
- Yeterliyse `_deduct_pantry`: her `ingredient_id` için `pantry_items.quantity -= Standart_Miktar`.
- Sonra `meal_log` eklenir ve `daily_nutrient_totals` güncellenir (toplam_kalori_kcal / porsiyon_sayisi × servings_consumed eklenir).

---

## rag_retrieval_log

- Her suggest çağrısında kullanıcı mesajı kaydedilir → `message_id`.
- Retrieval sonrası: `query_text`, `retrieved_sources` (recipe_id + score listesi), `top_k` yazılır.

---

## LLM (LangChain)

- Şu an **LLM kullanılmıyor**; `assistant_text` ve kart `reason` metinleri backend’de sabit/simple.
- `llm_service.py` ileride LangChain ile yapılandırılmış çıktı (assistant_text, kart açıklamaları) için kullanılacak; güvenlik kuralları her zaman backend’de kalacak.
