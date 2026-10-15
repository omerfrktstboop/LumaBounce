# LumaBounce — Tutunma ve Büyüme Planı

Tarih: 14 Ekim 2026. Kaynak: proje değerlendirmesi (gerçek cihaz ekran
görüntüleri, mağaza varlıkları, ekonomi kodu ve 200 bölümün tek tip ölçümü).

**Özet:** Teknik temel sağlam (fizik doğrulamalı bölümler, 6 dil, öğretici,
erişilebilirlik, kayıt güvenliği). Oyunun tutmasını engelleyecek konular teknik
değil: mağazadaki ilk izlenim, ilk 20 bölümün zorluğu, his (müzik ve görsel
enerji), geri dönmek için sebep olmaması ve yayından sonra ölçüm yapılamaması.

---

## Öncelik sırası

| Öncelik | İş | Bölüm |
|---|---|---|
| P0 — yayından önce | Mağaza öne çıkan görselini gerçek oyundan yeniden yap | 1 |
| P0 | Production analitiğini aç, bölüm hunisi olaylarını ekle | 6 |
| P0 | Ödüllü reklamla coin + mağaza fiyat dengesi | 5 |
| P0 | 4–15. bölümlerin nişan toleransını genişlet | 3 |
| P1 — ilk güncelleme | ~~Müzik~~ (kaldırıldı — ürün kararı) | 4 |
| P1 | Işık ve görsel enerji turu | 2 |
| P1 | Günlük bölüm + giriş serisi | 5 |
| P1 | 151–200 taslaklarını elle düzenle | 3 |
| P2 — sonra | Play Games başarımları ve sıralama | 5 |
| P2 | Dünyaya özel arka planlar | 2 |
| P2 | Başarı paylaşımı | 5 |

---

## 1. Mağaza ve ilk izlenim

- [x] **Öne çıkan görsel yanıltıcı.** `assets/store/play_store_feature_graphic_1024x500.png`
  mor neon, yandan bakışlı platformlar, rampalar ve dikenli çark gösteriyor; oyun
  dikey, lacivert-camgöbeği ve minimal. Beklentisi boşa çıkan oyuncu siler ve
  düşük puan verir; Google Play'in yanıltıcı görsel kuralına da takılabilir.
  → Yenisi gerçek oyun render'ından: `tools/capture_store_assets.gd` →
  `builds/store_assets/<dil>/feature_graphic.png` (6 dil). Eski dosya Play
  Console'da değiştirilince silinebilir.
- [ ] **İkon çok koyu.** `assets/icons/luma_bounce_icon_v2_192.png` ve adaptive
  v2 katmanları oyunla tutarlı, ama renkli ikonların arasında küçük boyutta
  kayboluyor. Daha parlak zemin veya daha güçlü ışık.
- [x] **Ekran görüntüleri:** gerçek oynanış, üstünde kısa açıklama yazıları —
  7 kare × 6 dil, oyun içi metin de o dilde (`tools/capture_store_assets.gd`).
- [ ] **Tanıtım videosu:** 15–30 sn, portal ve çok sekmeli atış anları.
  (Play video için YouTube bağlantısı ister; yapılmadı.)
- [x] **ASO:** başlıkta anahtar kelime ("LumaBounce: Physics Puzzle" ve
  karşılıkları), kısa açıklamada çek/nişan/sektir kelimeleri.
- [x] **Mağaza metnini 6 dile çevir** — `docs/store/STORE_LISTING.md`
  (başlık, kısa/tam açıklama, "Yeni neler var"); sınırlar
  `tools/check_store_listing.gd` ile denetlenir.

## 2. Görsel tasarım ve renkler

İyi olan: tutarlı tasarım sistemi (`Palette`, `PaletteThemes`, `UIMetrics`),
okunaklı ve sakin, premium his.

Sorunlar:
- Her şey çok koyu ve tek tonlu; 1. bölüm boş karanlıkta bir kareden ibaret.
- Paneller mat gri kapsüller, hedef sıradan bir kare.
- Dünyalar yalnızca vurgu rengiyle ayrışıyor; arka plan hep aynı.
- Oyunun adı "Luma" (ışık) ama ışık hiçbir yerde kahraman değil.
- 20:9 telefonda üst bilgi şeridiyle oyun alanı arasında ekranın ~%20'si boş.

Yapılacaklar (sadelik korunarak, ışık öne çıkarılarak):
- [x] Panellere neon kenar / ince parlak çerçeve (bostayken soluk hale, temasta
  kısa flaş — `BouncePanel.flash`).
- [x] Hedefe kimlik: merkezde nefes alan kristal; isabette yanar, kare dolar,
  ışınlar + çift halka.
- [x] Top izi daha parlak (eklemeli karışım); sekmelerde `LightFlash`.
- [x] Her dünyaya kendi arka plan motifi (yıldız, ızgara, aurora, prizma) ve
  hafif parallax (`WorldMotif`).
- [ ] Uzun ekranlarda boşluğu kapat (HUD konumu veya oyun alanı ölçeği).

Kısıt: görsel işler fizik alanlarına dokunmaz (bkz.
`.claude/skills/lumabounce-visual-polish`). `HAZARD`, `COIN`, `PORTAL_*`
renkleri dünyadan bağımsız kalır.

## 3. Bölümler ve zorluk eğrisi

**Ölçüm yöntemi:** her bölüm aynı ızgarayla tarandı (±3° açı, ±100 güç,
tuğlalar kırık, `LevelSolver.scan` + `analyse_robust`). Sayı, dört komşusu da
isabet eden atış hücresi adedidir; yüksek sayı = geniş nişan toleransı = kolay.
Doğrulayıcının daha ince ızgarası (1° / 25) farklı mutlak değerler verir, ama
bu tablo bölümleri birbiriyle karşılaştırmak için tek ölçüdür.

| Bölümler | Ort. tolerans | Yorum |
|---|---|---|
| 1–3 | 14–16 | Rahat başlangıç |
| **4–25** | **0–3** | **5–12. bölümler hassas nişan istiyor** |
| 26–50 | ~14 | Tuğlalar kırılınca rahatlıyor |
| 51–150 | 2–4 | Sürekli dar |
| 151–200 | 12–18 | Taslaklar belirgin şekilde kolay |

5'li adım ortalamaları: 1:9 · 6:0 · 11:0 · 16:1 · 21:0 · 26:21 · 31:16 · 36:15 ·
41:11 · 46:7 · 51:5 · 56:6 · 61:6 · 66:0 · 71:2 · 76:5 · 81:1 · 86:7 · 91:4 ·
96:2 · 101:1 · 106:0 · 111:4 · 116:1 · 121:2 · 126:1 · 131:0 · 136:2 · 141:10 ·
146:5 · 151:36 · 156:19 · 161:13 · 166:11 · 171:11 · 176:12 · 181:12 · 186:9 ·
191:15 · 196:13

Yapılacaklar:
- [ ] **5–21 arası en büyük terk riski.** Üst üste binenler:
  - Hassas nişan isteyen bölümler (5–12).
  - 1–10'da 3 yıldız için tek atış şartı (`three_star_max_shots = 1`).
  - 21'deki 40 yıldızlık kapı (`LevelLibrary.STAR_GATES`).
  - Nişan kılavuzunun ilerledikçe kısalması (`Launcher.guide_visibility_ratio`).

  4–15'i genişlet; 3 yıldız ustalık için zor kalabilir ama 1–2 yıldız rahat olmalı.

  **Yapılan (Ekim 2026, zorluk bilerek korunarak):**
  - Ölçüm hatası düzeltildi: çözücü topun ve hedefin bölüme özgü boyutunu
    (`ball_scale` %78, `target_scale`) yok sayıyordu. Gerçek boyutla 4–8 makul
    çıktı; asıl dar olanlar 9, 11, 13, 14, 16, 17.
  - Hedefi büyütmek denendi, **işe yaramadı** (%30 büyütme isabeti yalnızca
    %3–10 artırıyor; darboğaz panel aralıkları).
  - Yalnızca iki aykırı bölüme küçük panel dokunuşu: 11 (bir panel 12 px) isabet
    %0,70 → %1,22; 13 (iki panel 12 px / 3°) %0,42 → %0,94.
  - 1–15'te kısa ipucu ücretsiz.
  - 3 yıldız kuralı ve 21. bölüm kapısı **bilerek değiştirilmedi**.
- [ ] **Testere dişi eğri:** her 25'lik bant kolay başlayıp zor bitsin. Şu an
  bantlar arası düzensiz (126–150, 101–125'ten kolay; 151–200 hepsinden kolay).
- [ ] **151–200 taslakları:** düzenlerken zorluğu kademeli artır; şu an 51–150'den
  çok daha toleranslı.
- [ ] **126–150 isim uyuşmazlığı:** isimler lazer vaat ediyor ("Lazer Kapanı",
  "Işın Düğümü") ama içerik çoğunlukla kayan bariyer. İsimleri değiştir ya da
  lazer ekle (`docs/LEVEL_PHASES.md` notuna bkz.).
- [ ] **149 ve 150:** doğrulayıcıya göre sağlam çözüm yok; elle geçilebiliyor ama
  çok dar. Final bölümünün genişletilmesi önerilir.
- [ ] **Tekrarlanan isimler:** 1–150'de yalnızca 131 farklı isim var (19 tekrar);
  tekrarlar oyuncuya özensizlik gibi görünebilir.

## 4. His ve ses

- [ ] ~~**Müzik.**~~ **Kaldırıldı (ürün kararı, Ekim 2026):** denendi, oyunda
  gereksiz bulundu. Oyun yalnızca efekt sesleriyle çıkıyor; Ayarlar'daki müzik
  kaydırıcısı da kalktı. Aşağıdaki not yalnızca kayıt için.
  Her dünya için ayrı sakin synth parçası + menü parçası
  (`assets/audio/music/`, `tools/generate_sfx.py` ile dikişsiz döngü üretilir).
  Ekran geçişiyle çapraz geçer, aynı dünyada bölümden bölüme yeniden başlamaz,
  tam ekran reklamda ve uygulama arka plandayken durur. Ayarlar'daki müzik
  kaydırıcısı artık gerçekten bir şey kontrol ediyor. Parçalar kısa (19–29 sn);
  ileride daha uzun/çeşitli varyasyonlar düşünülebilir.
- [x] **Ödül anlarını büyüt:**
  - [x] Hedefe isabette kutlama (mor ışık patlaması, yanan hedef).
  - [x] Yıldızların uçarak gelmesi (her başarıda; iniş parıltısı + yükselen
    `star.wav` üçlüsü), coin ödülü yıldızlardan sonra pop.
  - [x] Çok sekmeli atışta "N SEKME!" yazısı (3+; 5+ büyük ve mor).
  - [ ] Son yaklaşmada kısa yavaşlama — **yapılmadı:** `Engine.time_scale`
    topun integrasyon adımını da değiştirir ve `LevelSolver` ile birebir
    determinizmi bozar. Yalnızca görsel bir yöntem (kamera/zoom) gerekir.

## 5. Ekonomi ve geri dönme sebebi

Mevcut durum (`scripts/levels/coin_economy.gd`, `scripts/cosmetics/cosmetic_catalog.gd`):
- Kazanç: başlangıç 3, her 5 yeni bölümde +2, her 10. bölümün ilk 3 yıldızında +1.
  200 bölümün tamamı ≈ 100 coin.
- Mağaza: 10 ücretli kozmetik, toplam 1080 coin (40–215 arası). 50 bölüm
  oynayan biri hiçbir şey alamıyor.
- Kısa ipucu 2 coin; coin kıt olduğu için o da az kullanılır.

Yapılacaklar:
- [x] **Ödüllü reklamla coin'i bağla.** Mağazada "ÜCRETSİZ COIN" kartı: reklam
  başına +5, günde 5 hak (`PLACEMENT_COIN_BONUS`, sayaç `WalletStore` şema 3).
- [x] **Fiyat/kazanç dengesi:** her ilk bitiriş +1, her ilk 3 yıldız +1, her 10.
  bölüm ayrıca +3 → kampanya 260–460 coin. Fiyatlar 25–130, mağaza toplamı 660.
- [ ] **Günlük sistem:** günlük giriş ödülü (`DAILY_LOGIN_REWARD`), görevler ve
  seri kodda var (`scripts/retention/`) ama bilerek gizli
  (`.claude/skills/lumabounce-visual-polish` §7 — lansman ürün kararı). Kararı
  gözden geçir: en azından günlük bölüm + giriş serisi.
- [ ] **Play Games Services:** başarımlar şu an yalnızca oyun içinde. Başarımlar
  ve toplam yıldız sıralaması görünürlük getirir.
- [ ] **Paylaşım:** bölüm/başarı paylaşımı (sonraki sürüm).

## 6. Ölçüm (yayından önce şart)

- [ ] **Production analitiği kapalı.** `scripts/app_root.gd` analitiği yalnızca
  debug ve `production` olmayan build'de açıyor; yayın sürümü `NoOpAnalyticsProvider`
  kullanıyor. GameAnalytics 3.1.0 karantinada (`docs/ANALYTICS.md`). Yayından
  sonra oyuncuların nerede bıraktığı görülemez; yukarıdaki zorluk tahminleri
  ancak bu veriyle doğrulanabilir.
- [ ] Analitik sağlayıcıyı aç (Firebase veya GameAnalytics); UMP izin akışı hazır.
- [ ] Olaylar: bölüm başlatma / başarısızlık / tamamlama, atış sayısı, süre,
  ipucu ve reklam olayları, yıldız kapısında takılma.
- [ ] **Yumuşak lansman:** önce birkaç ülke. Sektördeki kaba kural: gündelik
  bulmacada ertesi gün geri dönüş %35+, 7. gün %10+ iyi sayılır. Bölüm hunisine
  bakıp düzelt, sonra genel yayına çık.

---

## Güçlü yanlar (korunacaklar)

- Her bölüm gerçek fizikle doğrulanıyor (`LevelSolver` + `verify_levels.gd`).
- Mekanik temposu: her 25 bölümde bir yeni fikir, tanıtım kartlarıyla.
- Etkileşimli ilk atış öğreticisi, ipucu sistemi, 6 dil, renk körlüğüne duyarlı
  işaretler, güvenli kayıt ve şema göçü.
- Dengeli reklam sıklığı (5 tamamlamada bir, 3 dk bekleme), `remove_ads`.
