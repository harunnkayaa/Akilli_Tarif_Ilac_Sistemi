# "Tarif bulunamadı" — Teşhis Rehberi

Bu mesaj, **retrieval** aşamasında hiç tarif id’si dönmediği için oluşur (`retrieve_recipe_ids` boş liste döner).

## 1. rag_documents dolu mu, şema doğru mu?

Uygulamanın bağlandığı veritabanında çalıştırın:

```sql
-- Varsayılan: tablo rag.rag_documents
SELECT COUNT(*) FROM rag.rag_documents WHERE source_table = 'recipes';
```

- **0 ise:** RAG tablosu boş veya tarifler yüklenmemiş. Önce `rag_documents` doldurulmalı (embedding’li chunk’lar, source_table='recipes', source_pk=tarif_id).
- **>0 ise:** Aşağıdaki adımlara geçin.

## 2. Hangi şema kullanılıyor?

`.env` veya ortam değişkeninde:

- `RAG_SCHEMA` boş veya `rag` (varsayılan) → tablo `rag.rag_documents`
- `RAG_SCHEMA=public` → tablo `public.rag_documents`

Tablonuz hangi şemadaysa, uygulamanın aynı şemayı kullandığından emin olun.

## 3. Vektör mü, metin fallback mı?

- **OPENAI_API_KEY** set ise: sorgu önce **embedding** ile vektör araması yapar.
  - `rag_documents.embedding` sütunu **768 boyut** (text-embedding-3-small) olmalı.
  - Boyut uyuşmazsa veya embedding NULL ise sonuç dönmeyebilir.
- **OPENAI_API_KEY** yok veya embedding hata verirse: **ILIKE** (metin) fallback kullanılır.
  - Önce tam ifade aranır (örn. "akşam yemeği öner").
  - Sonuç yoksa kelime bazlı aranır (örn. "akşam" VEYA "yemeği" geçen dokümanlar).

## 4. Hızlı kontrol (recipes tablosu)

Tariflerin kendisi `recipes` tablosunda olmalı; RAG sadece arama için:

```sql
SELECT COUNT(*) FROM recipes;
SELECT tarif_id, tarif_adi FROM recipes LIMIT 3;
```

## 5. Özet checklist

| Kontrol | Ne yapılır |
|--------|------------|
| rag_documents dolu mu? | Yukarıdaki COUNT sorgusu; 0 ise RAG doldurulmalı. |
| Şema uyumu | RAG_SCHEMA ile tablonun şeması aynı mı? |
| Vektör boyutu | Embedding 768 boyut mu? (text-embedding-3-small) |
| API key | OPENAI_API_KEY set mi? (yoksa ILIKE kullanılır) |

En sık neden: **rag_documents tablosunda source_table='recipes' ile satır yok** (veya farklı şemada aranıyor).
