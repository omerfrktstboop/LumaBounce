# LumaBounce — Yayın ve Sürüm Rehberi

Bu belge Play Store sürümü almak ve sonraki güncellemeleri **oyuncu ilerlemesini
bozmadan** yayınlamak için gereken adımları içerir.

Denetimi her zaman önce otomatik araçla yap:

```
godot --headless --path . --script res://tools/check_release_readiness.gd
```

Araç hiçbir şeyi değiştirmez, yalnızca raporlar. `BLOKER` varsa çıkış kodu 1'dir.

---

## 1. Sürüm numaraları

Üç sürüm ayrıdır ve `scripts/game_version.gd` içinde tutulur:

| Alan | Anlamı | Ne zaman artar |
|---|---|---|
| `GameVersion.GAME` | Mağaza sürümü (semver) | Her yayında |
| `GameVersion.SAVE_SCHEMA` | Kayıt **dosya yapısı** (şu an **2**) | Yalnızca kayıt alanları değişince |
| `GameVersion.CONTENT` | Bölüm/içerik paketi | Yeni bölüm/tema eklenince |

`SAVE_SCHEMA` bilerek ayrıdır: oyun 20 kez güncellense de kayıt yapısı
değişmediyse 1 kalır ve hiçbir migration çalışmaz.

### Android `versionCode` — kritik
`export_presets.cfg` içindeki `version/code` **her Play Store yüklemesinde
artmalıdır**. Aynı `versionCode` ikinci kez kabul edilmez.
`version/name` ise oyuncuya görünen metindir ve `GameVersion.GAME` ile elle
eşlenmelidir (Godot bunu otomatik okumaz).

---

## 2. Yayın öncesi kontrol listesi

- [ ] `check_release_readiness.gd` → BLOKER yok
- [ ] `check_blocks_and_gate.gd` → 0 hata
- [ ] `check_obstacles.gd` → 0 hata
- [ ] `verify_levels.gd` → çözülemezlik, çakışma veya HUD ihlali yok
- [ ] `version/code` bir önceki yüklemeden büyük
- [ ] `version/name` = `GameVersion.GAME`
- [ ] `Android Release` paket adı `com.ofsgames.lumabounce`
- [ ] Target API = 36; Android SDK Platform 36 kurulu
- [ ] `export_format=1` (AAB) ve `use_gradle_build=true`
- [ ] `res://android/build` Gradle şablonu kurulu
- [ ] Release filtresi yalnızca dev-only addonları dışlıyor; `addons/*` kullanılmıyor
- [ ] AdMob v7 eklentisi etkin; debug APK yalnızca Google test reklam birimlerini kullanıyor
- [ ] UMP formu ilk açılışta test edildi; Ayarlar'da gerekli kullanıcılara gizlilik seçenekleri görünüyor
- [ ] `check_analytics_phase10.gd` geçiyor; production dashboard'da debug event yok
- [ ] GameAnalytics etkinleştirilecekse `docs/ANALYTICS.md` uyumluluk karantinası çözüldü ve staging internal test tamamlandı
- [ ] `godot_mcp_toolkit`, debug paneli, DBG rozeti ve level editor release paketinde yok
- [ ] Launcher ikonları dolu
- [ ] Keystore hazır ve **repoda değil**
- [ ] AAB/APK içindeki bütün `.so` dosyaları 16 KB page-size için doğrulandı
- [ ] Gerçek cihazda: yeni oyuncu akışı + güncelleme akışı denendi

---

## 3. Android release zinciri

Sürüm kontrolündeki iki preset farklı amaç taşır:

| Preset | Çıktı | Kullanım |
|---|---|---|
| `Android Release` | `builds/lumabounce-release.aab` | Google Play production |
| `Android Debug` | `builds/lumabounce-debug.apk` | Cihaza kurulan debug/playtest |

İkisi de Gradle ve target API 36 kullanır. Release preset yalnızca dev araçlarını
(`tools`, kök test betikleri, `godot_mcp_toolkit`, debug panel ve level editor) dışlar. **`addons/*`
toplu olarak dışlanmaz**; gelecekte AdMob ve Google Play Billing runtime pluginleri
`addons/` altında pakete girebilmelidir.

### 3.1 MANUEL: SDK, JDK ve Gradle şablonu

1. Android Studio SDK Manager ile `platforms;android-36`, güncel Platform-Tools,
   Build-Tools ve Command-line Tools kur.
2. Godot'ta `Editor → Editor Settings → Export → Android` altında `Java SDK Path`
   (JDK 17) ve `Android SDK Path` alanlarını ayarla.
3. Godot 4.7.1 ile eşleşen tam export template paketini kur. Paket
   `android_source.zip` içermelidir.
4. `Project → Install Android Build Template...` ile `res://android/build`
   oluştur. Bu adım AAB ve sonraki AdMob/Billing pluginleri için gereklidir.

API 36 kurulamazsa preset'i sessizce 35'e düşürme; export'u durdur ve engeli çöz.
31 Ağustos 2026'dan itibaren yeni mobil uygulamalar ve güncellemeler API 36 veya
üstünü hedeflemelidir.

### 3.2 MANUEL: release imzası

Keystore'u, alias'ı veya parolayı **repoya ya da `export_presets.cfg` içine yazma**.
Anahtarı ayrı, erişimi sınırlı ve yedekli bir konumda tut. Export yapılacak terminal
oturumunda Godot'un resmi ortam değişkenlerini kullan:

```powershell
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = "C:\secure\lumabounce-release.jks"
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = "<KEY_ALIAS>"
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = "<PASSWORD>"
```

Bu değerleri bir `.ps1`, `.env`, CI logu veya shell geçmişine kaydetme. İş bittikten
sonra terminali kapat veya değişkenleri temizle.

### 3.3 Production AAB

```powershell
godot --headless --path . --export-release "Android Release" builds/lumabounce-release.aab
```

GUI alternatifi: `Project → Export → Android Release → Export Project`; **Export
With Debug** kapalı olmalı. `Android Debug` presetini APK playtest için kullan.

### 3.4 Android 15+ ve 16 KB page size

Godot motoru ve ileride eklenecek her native AdMob/Billing SDK'sı `.so` dosyası
taşıyabilir. Her plugin ekleme veya sürüm yükseltmeden sonra production çıktısını
Android Studio APK Analyzer ile incele; tüm native kütüphanelerde alignment uyarısı
olmadığını doğrula. Ayrıca 16 KB Android 15+ emülatöründe:

```text
adb shell getconf PAGE_SIZE
```

sonucu `16384` olmalı. APK türevi için `zipalign -c -P 16 -v 4 app.apk` çalıştır
ve temel açılış/oynanış akışını cihazda dene. Native plugin yokken bu faz yalnızca
prosedürü hazırlar; plugin geldiğinde onun 16 KB uyumluluğu ayrıca doğrulanmalıdır.

---

## 4. Kayıt sistemi ve güncelleme güvenliği

Kayıt dosyası: `user://save.cfg` · Yedek: `user://save.cfg.bak`

**Bölümler değişmez `uid` ile anılır** (`level_027`), sıra numarasıyla değil.
Bunun sebebi doğrudan güncelleme güvenliğidir: araya yeni bir bölüm eklemek
veya sırayı değiştirmek, sayı tabanlı bir kayıtta oyuncunun tamamladığı
bölümleri **başka bölümlere kaydırır**.

Yükleme sırası:
1. `save.cfg` okunur
2. Okunamazsa `save.cfg.bak` denenir ve kurtarılan durum hemen geri yazılır
3. İkisi de olmazsa sıfırdan başlanır (log'a yazılır, oyun açılır)

Yazma sırasında önce mevcut **sağlam** dosya yedeklenir; bozuk bir dosya
yedeklenmez, yoksa kurtarma şansı yok olurdu.

### Şema göçü
Dosyadaki `save_schema_version` okunur. Anahtar yoksa kayıt şema 0'dır
(uid öncesi, tamsayı anahtarlı) ve `_migrate_from_v0()` ile okunur; ilk
`save()` dosyayı yeni şemada yazar. Göç kayıpsızdır ve oyuncu fark etmez.

İleri sürümden gelen kayıt (oyuncu eski sürüme döndü) **silinmez**: bilinen
alanlar okunur, bilinmeyenlere dokunulmaz.

**Şema 1 → 2** (dil, ekran sarsıntısı, nişan yardımı eklendi): veri dönüşümü
gerekmez, yeni alanların hepsi savunmacı okunur ve makul bir varsayılana
düşer. Numara yine de arttı, çünkü sürümün anlamı "bu kaydı hangi alan
kümesini bilen sürüm yazdı".

### Luma Coin ve kozmetikler — sıfırlama beklentisi

`user://wallet.cfg` (şema 2) bakiyeyi, ipucu açılımlarını, **satın alınmış
kozmetikleri** ve seçili kozmetikleri tutar.

**"İlerlemeyi sıfırla" bu dosyaya dokunmaz.** Bölümler, yıldızlar ve
tamamlananlar silinir; Coin bakiyesi, açılmış ipuçları ve kozmetik sahipliği
**kalır**.

Gerekçe: kozmetik *satın alınmış* bir şeydir, kazanılmış bir ilerleme değil.
215 Coin'e alınan bir hedef efektini "baştan başla" ile kaybetmek, sıfırlamayı
bir cezaya çevirirdi. Bugün Coin yalnızca oyun içinde kazanıldığı için bu bir
tercih; **gerçek parayla Coin satılırsa zorunluluk hâline gelir** ve bakiyenin
cihazda değil sunucuda tutulması gerekir.

Oyuncuya bu ayrımın ayarlar ekranındaki onay metninde belirtilmesi önerilir
("İlerlemen silinecek; Coin ve kozmetiklerin kalacak").

---

### Ayarlar nerede saklanır
İki ayrı dosya, bilerek:

| Dosya | İçerik |
|---|---|
| `user://save.cfg` → `[settings]` | dil, titreşim, ekran sarsıntısı, nişan yardımı |
| `user://audio_settings.cfg` | sessize alma, müzik ve efekt seviyesi |

İkisi de `ProgressStore.reset()` tarafından **korunur**: ilerleme silmek
oyuncu tercihlerini silmez. "Baştan başla" diyen oyuncunun anlamadığı bir
dile dönmesi kabul edilemez.

---

## 5. Yeni bölüm ekleme adımları

1. `levels/level_NNN.tres` dosyasını oluştur (mevcut bir bölümü kopyalamak en kolayı).
2. `level_id` alanını dosya numarasıyla aynı yap.
3. `LevelLibrary.LEVEL_COUNT` değerini güncelle.
4. Doğrula:
   ```
   godot --headless --path . --script res://tools/verify_levels.gd -- --level NNN
   ```
   Bu komut yayın blokerlerini ölçer. Dar rota, mekanik kestirmesi ve bölüm
   ayarı uyarılarını da hata koduna katmak için tasarım çalışmasında
   `--strict-design` ekle.
5. Tekrar kontrolü:
   ```
   py -3 tools/find_duplicate_levels.py
   ```
   Rapor üç ayrı "aynı"yı ayırır. **Birebir aynı** ve **ayna kopyası** kabul
   edilemez. **Aynı iskelet** (aynı fırlatıcı + hedef + panel yerleşimi) tek
   başına kusur değildir — bir şablonun üzerine farklı mekanik kurmak meşru
   bir tasarımdır — ama aynı iskelet birkaç bölümde tekrarlanıyorsa bant
   monotonlaşır. Kırmak için:
   ```
   godot --headless --path . --script res://tools/diversify_skeletons.gd -- --only 42,43,44
   ```
   Bu araç engelleri, tuğlaları, yıldız eşiklerini ve adı **korur**; yalnızca
   panel ve hedef yerleşimini kaydırır. Kaydetmeden önce hem gerçek
   `LevelSolver` taramasından geçirir hem de yeni iskeletin kütüphanedeki
   hiçbir bölümle eşleşmediğini doğrular.
6. **Çeviri ekle.** Bölüm adını ve öğretici metnini `assets/i18n/levels.csv`
   dosyasına ekle (anahtar = Türkçe metnin kendisi). Unutursan bölüm İngilizce
   oyunda Türkçe adıyla görünür; `check_blocks_and_gate.gd` bunu yakalar
   (`_test_translation_coverage`).
7. `GameVersion.CONTENT` değerini artır.

**Sırayı değiştirmek istersen** bölüm dosyasındaki `display_order` alanını
kullan; `level_uid` sabit kaldığı sürece kayıtlar bozulmaz.

---

## 6. Diller

Kaynak dil **Türkçe**. Çeviri tabloları `assets/i18n/`:

İlk sürümde desteklenen diller: **Türkçe, İngilizce, İspanyolca, Brezilya
Portekizcesi, Almanca ve Fransızca**.

| Dosya | İçerik |
|---|---|
| `ui.csv` | arayüz metinleri |
| `levels.csv` | 125 bölüm adı + 13 öğretici metni |

**Anahtar, Türkçe metnin kendisidir.** Bunun sebebi doğrudan bakım maliyeti:
`LEVEL_042_NAME` gibi anahtarlar kullanılsaydı 125 bölüm dosyasının hepsine
dokunmak gerekirdi ve `.tres` dosyaları insan tarafından okunamaz hale
gelirdi. Bu şekilde çevirisi olmayan bir metin ekranda **boş değil, Türkçe**
görünür.

Godot `Control` metinlerini otomatik çevirir, dolayısıyla sahnelerdeki ve
koddaki düz metinler için ek bir şey yapmak gerekmez. **İstisna
biçimlendirilmiş metinlerdir**: `tr()` biçimlendirmeden **önce**
çağrılmalıdır, çünkü otomatik çeviri hazır metni (`"BÖLÜM 5"`) arar ve
tabloda bulamaz. Doğrusu `tr("BÖLÜM %d") % id`.

### Yeni dil ekleme
1. Her iki CSV'ye dil kodu sütunu ekle (ör. `de`).
2. `Locale.SUPPORTED` ve `Locale.DISPLAY_NAMES` içine kodu ekle — dilin adı
   **kendi dilinde** yazılmalı ("Deutsch", "Almanca" değil): dil arayan
   oyuncu mevcut dili okuyamıyor olabilir.
3. `project.godot` → `internationalization/locale/translations` içine yeni
   `.translation` dosyalarını ekle.
4. Editörü bir kez çalıştır (`godot --headless --editor --path . --quit`) ki
   CSV'ler yeniden içe aktarılsın.

Dil tercihi `[settings]` bölümünde saklanır ve `ProgressStore.reset()`
tarafından **korunur**. Tercih boş olması "oyuncu henüz seçmedi" demektir ve
cihazın dili kullanılır; bu "tr" seçmiş olmakla bilerek ayrı tutulur.

---

## 7. Sonraki sürümlerde eklenecekler için hazır zemin

Aşağıdakiler **uygulanmadı**, ama mevcut yapı bunlara engel değil:

| Özellik | Nereye bağlanır |
|---|---|
| Yeni tema/dünya | `LevelData.theme_id` + `PaletteThemes` |
| Yeni engel türü | `ObstacleData.Kind` + `ObstacleGeometry` + `LevelObstacle` (üçü birlikte) |
| Skin sistemi | `ProgressStore` `[settings]` bölümü |
| Reklam / ödül | `ProgressStore` genişletilebilir alanları |
| Günlük görev / başarım | Yeni bölüm + yeni şema sürümü (migration hazır) |
| Sonsuz mod | `LevelGenerator` zaten çalışma zamanında bölüm üretebiliyor |

Yeni kayıt alanı eklerken: alanı ekle, `SAVE_SCHEMA`'yı artır, `_read`'e
savunmacı okuma koy. Eski kayıtlar varsayılana düşer, silinmez.

---

## 8. Google Play Billing / remove_ads

V1'de yalnızca `remove_ads` adlı **tek seferlik, non-consumable** ürün bulunur.
Coin paketi veya abonelik oluşturma. Fiyat uygulamada sabit yazılmaz; mağaza
kartı Google Play'in döndürdüğü yerelleştirilmiş fiyatı gösterir.

### Play Console manuel kurulumu

1. **Para kazanma > Ürünler > Uygulama içi ürünler** altında `remove_ads`
   ürününü oluştur ve etkinleştir.
2. Ürünü tek seferlik/non-consumable davranışla yayınla; çoklu adet ve
   consumable davranışı açma.
3. Internal testing sürümünü oluştur, lisans test kullanıcılarını ekle ve
   test cihazında Play Store'daki aynı Google hesabını kullan.
4. Uygulamayı doğrudan APK ile değil internal test Play bağlantısından kur;
   gerçek ürün sorgusu sideload build'de güvenilir şekilde test edilemez.
5. Başarılı, iptal, `PENDING`, already-owned, yeniden kurulum/restore ve çevrimdışı
   açılış senaryolarını dene. `PENDING` iken reklamlar kaldırılmamalıdır.
6. Satın alma sonrası interstitial'ın kapandığını; kısa ipucu rewarded teklifinin
   isteğe bağlı olarak kaldığını doğrula.

Kod testi:

```powershell
godot --headless --path . --script res://tools/check_billing_phase7.gd
```

Bu sürüm client-side restore/ack kullanır. Tek `remove_ads` ürünü için kapsam
bilerek sınırlıdır; ileride gerçek para ile Coin satılacaksa backend doğrulaması
ve sunucu otoriteli bakiye kurulmadan ürün açılmamalıdır.
