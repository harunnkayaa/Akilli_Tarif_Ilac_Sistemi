# Teslim Hazırlığı — İlerleme Notu

**Hedef:** Projeyi hocanın kendi bilgisayarında/telefonunda sorunsuz çalışacak hale getirmek.
**Son güncelleme:** 13 Ağustos 2026

---

## Proje Özeti

| Katman | Teknoloji |
|---|---|
| Mobil | Flutter 3.38.7 / Dart 3.10.7 |
| Backend | FastAPI + Uvicorn, SQLAlchemy 2.x, Python 3.13 |
| Veritabanı | PostgreSQL 16 + pgvector |
| AI | OpenAI `gpt-4o-mini` + `text-embedding-3-small` (768 boyut), LangChain |
| Auth | Kendi JWT'si (python-jose + passlib **pbkdf2_sha256**) |
| Bildirim | `flutter_local_notifications` — **Firebase yok**, credential gerekmiyor |
| Görseller | Diskte dosya, FastAPI `StaticFiles` ile `/static` altından servis |

**Akış:** Flutter → FastAPI (JWT) → PostgreSQL/pgvector → OpenAI
Flutter hiçbir zaman doğrudan OpenAI'a bağlanmaz; API key sunucuda kalır.

---

## Başlangıçtaki Asıl Sorun

Proje "benim bilgisayarımda çalışıyor" durumundaydı. Kod sağlamdı, **veri yoktu**:

- Migration sistemi yok (Alembic yok, `create_all` yok)
- 23 tablodan sadece 1'i için `CREATE TABLE` mevcuttu
- `recipes`, `recipes_raw`, `recipe_feedback`, `drug_food_interactions`, `rag.rag_documents`
  tablolarının SQLAlchemy modeli bile yoktu — yani projede hiçbir izleri yoktu
- Seed verisi yoktu
- `.gitignore` `*.sql` ve `*.dump` dosyalarını dışlıyordu

Yani veritabanı yalnızca geliştiricinin makinesindeki PostgreSQL'de yaşıyordu.

---

## Yapılanlar

### 1. Veritabanı taşınabilir hale getirildi ✅

`smart-db` container'ı 8 haftadır kapalıydı, volume sağlamdı. Başlatıldı ve dump alındı.

**Dosya:** `backend/db/init/01_smartapp.sql` (20 MB)

İçerik:

| Tablo | Kayıt |
|---|---|
| recipes | 1091 |
| rag.rag_documents | 1599 (embedding'lerin **tamamı dolu**, 768 boyut) |
| ingredients | 543 |
| drug_food_interactions | 282 |
| disease_nutrient_limits | 225 |

**Kişisel veri temizliği:** Dump'ta 12 gerçek kullanıcının e-postası vardı.
Geçici bir container'da `TRUNCATE users CASCADE` yapıldı, tek demo hesap eklendi.
*(Bu işlem dump kopyası üzerinde yapıldı; orijinal veritabanına dokunulmadı.)*

> **Demo giriş:** `demo@demo.com` / `Demo1234`

**Doğrulama:** Temiz bir container'a sıfırdan yüklendi, satır sayıları birebir eşleşti,
gerçek pgvector benzerlik araması çalıştırıldı (anlamsal olarak doğru sonuçlar döndü).

### 2. Docker'a alındı ✅

**Yeni dosyalar:**
- `backend/Dockerfile` — Python 3.13-slim sabit
- `backend/.dockerignore` — `.venv` (168 MB) ve `.env` imaja girmiyor
- `backend/requirements.lock.txt` — 60 paketin sürümü donduruldu
  *(orijinal `requirements.txt`'de hiçbir sürüm sabit değildi — büyük risk)*
- `docker-compose.yml` — **proje kökünde**, backend + db birlikte
- `.env.example` — key'siz şablon

**Değiştirilen:** `.gitignore` — dump'ın git'e girebilmesi için 1 satır istisna.

İlk `up` sırasında dump `docker-entrypoint-initdb.d` üzerinden otomatik yüklenir.
`depends_on: service_healthy` sayesinde backend, DB hazır olmadan başlamaz.

### 3. Sunucu adresi esnek yapıldı ✅

`frontend/mobile_app/lib/core/api_client.dart` içindeki sabit IP kaldırıldı:

```dart
static const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',   // Android emülatörü varsayılanı
);
```

Artık adres derleme anında veriliyor. **Bu, projedeki tek kod değişikliğidir.**

### 4. Uçtan uca test edildi ✅

`docker compose down -v` ile her şey silinip sıfırdan kuruldu, ardından emülatörde
gerçek APK ile test edildi:

| Test | Sonuç |
|---|---|
| Seed otomatik yüklendi | recipes=1091, rag_documents=1599 |
| Backend ayağa kalktı | 2 saniye |
| Demo hesapla giriş | Token alındı (165 karakter) |
| Görsel servisi | HTTP 200, image/jpeg |
| İlaç etkileşimi | "War" → Warfarin |
| Token'sız istek | 401 ile reddedildi |
| **Chat (gerçek OpenAI)** | **Tarif kartları fotoğraflarıyla döndü** |
| Bildirim | Emülatörde "Aldım/Ertele/Atla" bildirimi göründü |

---

## Mevcut Durum

```
1. ✅ Veritabanı taşınabilir
2. ✅ Docker (backend + db)
3. ✅ Adres esnek
4. ✅ APK derleniyor ve çalışıyor
5. ⏳ Yayına alma + teslim paketi   ← KALAN
```

**Şu anki APK:** `frontend/mobile_app/build/app/outputs/flutter-apk/app-release.apk` (86 MB)
İçinde `172.2.3.123:8000` gömülü → **sadece geliştiricinin yerel ağında çalışır.**
Bu bir test APK'sıdır, teslim sürümü değildir.

---

## Kalan İşler

### Yayına alma (hesap gerektirir)
1. **Neon** (neon.tech) — ücretsiz PostgreSQL, pgvector eklentisi aktif edilecek
   - Dump 20 MB, ücretsiz limit ~500 MB → rahat sığıyor
2. **Render** (render.com) — backend, mevcut `Dockerfile` ile deploy edilecek
3. Yayındaki adresle APK yeniden derlenecek:
   ```bash
   flutter build apk --release --dart-define=API_BASE_URL=https://<adres>
   ```
4. Backend'de `BASE_URL` de aynı adres yapılacak
   *(unutulursa uygulama çalışır ama tüm tarif görselleri kırık görünür)*

### Bilinen riskler
- **Cold start:** Ücretsiz Render 15 dk sonra uyur. Uygulamadaki bazı timeout'lar kısa
  (`boot_screen.dart` 6 sn, `auth_api.dart` 5 sn) → ilk açılışta hata görülebilir.
  **Çözüm:** UptimeRobot / cron-job.org ile `/health` adresine 10 dakikada bir ping.
  (`/health` DB'ye ve OpenAI'a dokunmaz, maliyeti yok.)
- **Süreklilik:** Ücretsiz katman ileride kapanabilir → Docker paketi de yedek olarak teslim edilmeli.

### Karar bekleyenler
- [ ] **OpenAI API key stratejisi** — key'i ZIP'e koymak mı, ayrı limitli key üretip
      teslim sonrası iptal etmek mi? *(Öneri: limitli ayrı key)*
- [ ] **4 eksik tarif görseli** — TR0367 (Pesto Soslu Makarna), TR0498 (Soğanlı Bulgur Pilavı),
      TR0791 (Tavuklu Domates Çorbası), TR0813 (Yoğurtlu Ispanak Kökü Salatası).
      DB'de kayıtlı ama dosyaları diskte yok → kırık görsel olur. *(Projede zaten böyleydi.)*
- [ ] **Log temizliği** — `api_client.dart`'taki `LogInterceptor` release APK'da da çalışıyor
      ve `requestBody: true` olduğu için giriş şifresini logcat'e düz metin yazıyor.
- [ ] **APK boyutu** — 86 MB. `--split-per-abi` ile ~30 MB'a iner.

### ✅ Commit + push tamamlandı (14 Ağustos)
~5 aylık birikmiş iş iki commit hâlinde GitHub'a gönderildi
(`harunnkayaa/Akilli_Tarif_Ilac_Sistemi`, `main`):
- `5423049` uygulama geliştirmeleri (1121 dosya, 1088 tarif görseli dahil)
- `d686384` teslim altyapısı (Docker, dump, docs)

`.gitignore`'daki `backend/app/static/recipes/` kuralı kaldırıldı — Render imajı
GitHub'dan derlediği için görsellerin repoda olması **zorunlu**, yoksa tüm tarif
fotoğrafları kırık çıkar. `.env` dosyaları gitignore'da, API key sızmadı (doğrulandı).

---

## Nasıl Devam Edilir

```bash
cd ~/Desktop/Akilli_Tarif_Ilaç_Sistemi

# Backend + veritabanını ayağa kaldır
cp .env.example .env          # OPENAI_API_KEY doldurulmalı
docker compose up --build

# Kontrol
curl http://localhost:8000/health          # {"status":"ok"}
curl http://localhost:8000/llm/ping        # llm_enabled: true

# APK derle (adres kendinize göre)
cd frontend/mobile_app
flutter build apk --release --dart-define=API_BASE_URL=http://<adres>:8000
```

**Önemli:** Telefondan yerel ağ üzerinden bağlanılacaksa `.env` içindeki `BASE_URL`
de aynı adres olmalı — görsel URL'leri oradan üretiliyor.

Veritabanını sıfırlamak için: `docker compose down -v` (dump tekrar otomatik yüklenir).

---

## Hedeflenen Teslim Yapısı

```
teslim/
├── README.md                     ← kurulum talimatı
├── docker-compose.yml
├── .env.example
├── backend/
│   ├── Dockerfile
│   ├── requirements.lock.txt
│   ├── db/init/01_smartapp.sql   ← şema + veri (kritik)
│   └── app/static/recipes/       ← 1088 tarif görseli
└── apk/
    └── app-release.apk           ← yayındaki adrese bakar
```
