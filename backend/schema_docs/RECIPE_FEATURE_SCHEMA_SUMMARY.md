# Tarif Öneri Modülü — Şema Özeti

## CSV'lardan Çıkarılan Tablolar ve Kolonlar

### 1. rag_documents (vektör arama)
| Kolon        | Veri Tipi              | Kısıt      |
|-------------|------------------------|------------|
| doc_id      | uuid                   | PRIMARY KEY |
| source_table| text                   | NOT NULL   |
| source_pk   | text                   | NOT NULL   |
| chunk_index | integer                | NOT NULL   |
| title       | text                   | NULL       |
| content     | text                   | NOT NULL   |
| metadata    | jsonb                  | NOT NULL   |
| embedding   | USER-DEFINED (vector)   | NULL       |
| created_at  | timestamptz            | NOT NULL   |
| updated_at  | timestamptz            | NOT NULL   |

- Kullanım: `source_table = 'recipes'` ile tarif chunk'ları; `source_pk` = tarif_id.
- Cosine benzerlik: `embedding <=> :query_embedding` ORDER BY, LIMIT top_k.

---

### 2. recipes
| Kolon              | Veri Tipi   | Kısıt      |
|--------------------|-------------|------------|
| tarif_id           | text        | PRIMARY KEY |
| tarif_adi          | text        | NOT NULL   |
| kategori           | text        | NULL       |
| porsiyon_sayisi    | integer     | NULL       |
| toplam_kalori_kcal | double precision | NULL |
| kullanici_puani    | double precision | NULL |
| kaynak_url         | text        | NULL       |
| fotograf_url       | text        | NULL       |
| malzemeler_listesi | text        | NULL       |
| tarif_adimlari     | text        | NULL       |
| malzemeler_json    | jsonb       | NULL       |

- **malzemeler_json** yapısı: `[{ "Birim", "Malzeme_Adi", "Tarif_Olcum", "Standart_Miktar" }, ...]`
- Kişi başı kalori: `toplam_kalori_kcal / porsiyon_sayisi`

---

### 3. Chat
**chat_sessions**
| Kolon      | Veri Tipi | Kısıt       |
|------------|-----------|-------------|
| session_id | uuid      | PRIMARY KEY |
| user_id    | uuid      | FOREIGN KEY |
| created_at | timestamptz | NOT NULL  |
| title      | text      | NULL        |

**chat_messages**
| Kolon      | Veri Tipi | Kısıt       |
|------------|-----------|-------------|
| message_id | uuid      | PRIMARY KEY |
| session_id | uuid      | FOREIGN KEY |
| role       | text      | NOT NULL    |
| content    | text      | NOT NULL    |
| created_at | timestamptz | NOT NULL  |

---

### 4. rag_retrieval_log
| Kolon            | Veri Tipi | Kısıt       |
|------------------|-----------|-------------|
| retrieval_id     | uuid      | PRIMARY KEY |
| message_id       | uuid      | FOREIGN KEY |
| query_text       | text      | NOT NULL    |
| retrieved_sources| jsonb     | NOT NULL    |
| top_k            | integer   | NOT NULL    |
| created_at       | timestamptz | NOT NULL  |

- retrieved_sources: `[{ "recipe_id": "...", "score": float }, ...]`

---

### 5. Kullanıcı bağlamı
**user_allergies**: id (PK), user_id (FK), ingredient_id (FK), raw_text, reaction, notes, is_custom, note  
**user_disliked_ingredients**: id (PK), user_id (FK), ingredient_id (FK), raw_text, reason, is_custom, free_text  
**user_drugs**: user_drug_id (PK), user_id (FK), drug_name, atc_code, drug_class, start_date, end_date, notes  
**user_diseases**: (user_id, disease_name) PK, user_id FK, disease_name, diagnosed_at, notes  

**drug_food_interactions**: id (PK), drug_name, drug_class, atc_code, **food_name_tr**, nutrient_focus, interaction_effect, mechanism, recommendation_tr, source_primary, source_url  
**disease_nutrient_limits**: id (PK), disease_name, nutrient_tag, limit_type, value, unit, condition_note, source_primary, source_url  

**daily_nutrient_totals**: (user_id, day) PK, user_id FK, day, total_energy_kcal, total_protein_g, total_fat_g, total_carbohydrate_g, total_sodium_mg, updated_at  

**pantry_items**: (user_id, ingredient_id) PK, user_id FK, ingredient_id, quantity, unit, expires_at, low_threshold, updated_at  

---

### 6. meal_log
| Kolon             | Veri Tipi   | Kısıt       |
|-------------------|-------------|-------------|
| log_id            | uuid        | PRIMARY KEY |
| user_id           | uuid        | FOREIGN KEY |
| tarif_id          | text        | FOREIGN KEY (recipes) |
| consumed_at       | timestamptz | NOT NULL    |
| servings_consumed | numeric     | NOT NULL    |
| notes             | text        | NULL        |

---

## İlişkiler (Tarif özelliği için)
- chat_sessions.user_id → users.user_id  
- chat_messages.session_id → chat_sessions.session_id  
- rag_retrieval_log.message_id → chat_messages.message_id  
- meal_log.user_id → users.user_id  
- meal_log.tarif_id → recipes.tarif_id  
- pantry_items.ingredient_id → ingredients.id (stok eşlemesi için Malzeme_Adi → ingredient_id gerekebilir)

---

## Tarif modülü için kullanılan tablolar
- **rag_documents** — vektör arama  
- **recipes** — tarif detayı, malzemeler_json, kalori  
- **chat_sessions**, **chat_messages** — sohbet  
- **rag_retrieval_log** — retrieval log  
- **user_allergies**, **user_disliked_ingredients** — alerji / sevmeme kuralları  
- **user_drugs**, **drug_food_interactions** — ilaç–gıda uyarıları  
- **user_diseases**, **disease_nutrient_limits**, **daily_nutrient_totals** — hastalık limit uyarıları  
- **pantry_items**, **ingredients** — stok kontrolü ve düşüm  
- **meal_log** — yemek loglama  
- **daily_nutrient_totals** — günlük besin güncellemesi  
