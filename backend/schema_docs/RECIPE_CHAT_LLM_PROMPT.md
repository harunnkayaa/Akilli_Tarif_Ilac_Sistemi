# Tarif Sohbeti — Davranış ve LLM Prompt Taslağı

## Nasıl Çalışıyor (Kullanıcıya Anlatım)

Tarif önerisi **stok durumunuzu ön planda tutar**:

- **Kilerinizdeki malzemeler** (Brokoli, Domates, Salatalık vb.) ile yapılabilecek tarifler **daha üst sırada** gelir.
- Hem “ne yemek istersiniz?” (mesaj) hem de “kilerde neler var?” (pantry) birlikte değerlendirilir.
- Kartlarda **Stokta olan** ve **Eksik** malzemeler gösterilir; böylece hangi tarifi ne kadar malzemeyle yapabileceğinizi görürsünüz.
- **Alerji / ilaç–gıda / hastalık limitleri** her zaman backend kurallarıyla uygulanır; asistan sadece metin üretir, güvenlik kararı vermez.

---

## Sıralama Mantığı (Backend, Deterministik)

- **Mesaj skoru:** Sorgunuzla anlamsal benzerlik (örn. “sebzeli akşam yemeği”).
- **Kiler skoru:** Kilerdeki malzeme adlarıyla tariflerin anlamsal eşleşmesi.
- **Stok skoru:** Tarifin ihtiyaç duyduğu (staple olmayan) malzemelerden kilerinizde **ne kadarının** karşılandığı (0–1).
- **Final skor:** `0.40×mesaj + 0.25×kiler + 0.40×stok − sevilmeyen_ceza`  
  → Stok durumu mesaj kadar ağır; kilerinizle uyumlu tarifler öne çıkar.

---

## LLM Entegrasyonu (USE_RECIPE_LLM=1)

Backend, asistan metnini üretmek için LLM’e şu **kullanıcı bağlamını** verir (system prompt + user mesajı):

- **Alerjiler:** Kullanıcının kayıtlı alerjileri (display_name/raw_text)
- **Sevmediği besinler:** Kullanıcının sevmediği malzemeler
- **Hastalıklar:** Kullanıcının kayıtlı hastalıkları (besin limitleri backend’de uygulanıyor)
- **İlaçlar:** Kullanıcının kullandığı ilaçlar (ilaç–gıda uyarıları backend’de ekleniyor)
- **Kiler özeti:** Pantry’den üretilen non-staple malzeme listesi (örn. "brokoli domates salatalık")

Buna ek olarak LLM’e **önerilen tarif listesi** (başlık, stokta olan / eksik malzemeler) verilir. Asistan, bu bağlama göre 1–3 cümlelik Türkçe yanıt üretir; stok ve kiler vurgulanır, uyarılar backend’in verdiği metinlerle sınırlı kalır.

---

## Prompt Taslağı (Sistem metni)

Aşağıdaki metin, LLM’e gönderilen **system prompt** taslağıdır (uygulama `llm_service.py` içinde kullanır).

```
Sen bir tarif öneri asistanısın. Kullanıcıya Türkçe yanıt verirsin.

ÖNEMLİ KURALLAR:
1. Öneriler backend tarafından belirlenir; sen sadece gelen kartları (tarif listesini) kullanıcıya açıklarsın.
2. Stok durumu önceliklidir: Kullanıcının kilerinde (Brokoli, Domates, Salatalık vb.) bulunan malzemelerle yapılabilecek tarifler bilinçli olarak öne çıkarılır. Bunu kısa ve samimi bir dille vurgula (örn. "Kilerinizdeki malzemelere göre özellikle şu tarifler sizin için uygun.").
3. Kartlarda "Stokta olan" ve "Eksik" malzemeler backend tarafından verilir. Bu listelere dayanarak konuş; yeni uyarı veya eksik malzeme uydurma.
4. Alerji, ilaç–gıda etkileşimi, hastalık limiti gibi güvenlik kararları backend’de alınır. Sen sadece backend’in ilettiği uyarı metinlerini (varsa) net ve anlaşılır şekilde özetleyebilirsin; asla kendi başına "bu tarif alerjinize uygun değil" gibi yeni güvenlik iddiasında bulunma.
5. Kısa, samimi ve bilgilendirici ol. Her kart için "neden bu tarif" kısmını backend’in verdiği bilgi (stok, kategori vb.) ile zenginleştirebilirsin; uydurma yapma.
```

---

## Özet

| Konu | Açıklama |
|------|----------|
| **Stok önceliği** | Sıralama formülünde stok ağırlığı yüksek (0.40); kilerle eşleşen tarifler üstte. |
| **Kullanıcıya mesaj** | "Kilerinizdeki malzemelere göre öneriler öne çıkarılır" ifadesi chat’te veya arayüzde kullanılabilir. |
| **LLM rolü** | Sadece metin (açıklama, özet, neden bu tarif); filtreleme ve güvenlik backend’de. |
| **Prompt taslağı** | Yukarıdaki blok, LLM entegrasyonunda system/context prompt olarak kullanılabilir. |
