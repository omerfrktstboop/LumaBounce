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
- [ ] `verify_levels.gd` → tüm bölümler geçiyor
- [ ] `version/code` bir önceki yüklemeden büyük
- [ ] `version/name` = `GameVersion.GAME`
- [ ] Paket adı doğru (aşağıya bak)
- [ ] `export_format=1` (.aab) ve `use_gradle_build=true`
- [ ] `exclude_filter` = `tools/*,addons/*`
- [ ] Launcher ikonları dolu
- [ ] Keystore hazır ve **repoda değil**
- [ ] Gerçek cihazda: yeni oyuncu akışı + güncelleme akışı denendi

---

## 3. Şu an açık olan maddeler (elle yapılmalı)

Bunlar bilerek otomatik değiştirilmedi; kimlik ve imzalama kararları yayıncıya aittir.

### 3.1 Paket adı — BLOKER
Mevcut: `com.lumabounce.game` · İstenen: `com.ofsgames.lumabounce`

> Paket adı ilk yüklemeden sonra **asla değiştirilemez**. Değiştirilecekse
> mağazaya ilk yüklemeden **önce** yapılmalıdır.

Godot editöründe: `Project → Export → Android → Package → Unique Name`.

### 3.2 .aab çıktısı — BLOKER
Play Store `.apk` kabul etmiyor. Gereken:
- `gradle_build/use_gradle_build = true`
- `gradle_build/export_format = 1` (AAB)

Gradle build için Android SDK + JDK kurulumu ve
`Editor → Editor Settings → Export → Android` yolları gerekir.

### 3.3 Keystore
Bu depoda **keystore veya parola yoktur ve olmamalıdır**. Release imzalama
anahtarını ayrı ve yedekli tut; kaybedilirse uygulamanın güncellenmesi
imkânsız hale gelir.

`.gitignore` içine en az şunlar girmeli: `*.keystore`, `*.jks`, `builds/`.

### 3.4 İkonlar
`launcher_icons/*` boş; varsayılan Godot ikonuyla çıkar.

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
