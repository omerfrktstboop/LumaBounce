# Geri bildirim sonrası kod geliştirme planı

Tarih: 15 Eylül 2026. Durum: beş adımın kod ve yerel/uygun cihaz doğrulamaları
tamamlandı. Play test dağıtımı gerektiren yerel review diyaloğu gözlemi mağaza
yükleme kapsamının dışında. Ayrıntılar:
[IMPLEMENTATION_HANDOFF.md](IMPLEMENTATION_HANDOFF.md).

Son kullanıcı kararı: bölüm kaynaklarına dokunulmayacak. Mevcut 37 bölüm/test
uyuşmazlığı kayıt altında; testleri geçti gibi gösterilmeyecek.

## Kapsam ve kararlar

- Play Store açıklaması, ASO, mağaza görselleri ve mağazaya yükleme kapsam dışı.
- Kullanıcı kararı: Android Release kendi gerçek AdMob kimlikleriyle canlı
  reklam kullanacak. Android Debug Google demo reklam kimliklerini kullanacak.
- Mevcut mekanik tanıtım kartları, ilerleme kayıtları ve erişilebilirlik
  seçenekleri korunarak geliştirilecek.
- Oyun içindeki değerlendirme bağlantısı ve review entegrasyonu kapsama dahil;
  bunlar mağaza listelemesinde değişiklik gerektirmez.

## 1. Bölüm ve test uyuşmazlıklarını çöz

Mevcut durum: `check_blocks_and_gate.gd` 1534 başarılı, 39 başarısız kontrol
bildiriyor. Sorunlar 118, 126–136, 138–140 ve 148–150. bölümlerin blok/lazer
beklentilerinde. Başlangıç kaydı: `scratchpad/android-setup-blocks-check.log`.

- `levels/`, bölüm tasarım belgeleri, git geçmişi ve ilgili test beklentilerini
  karşılaştır; eski test beklentisiyle içerik hatasını ayır.
- Doğru tasarım kararı belirlendikten sonra ilgili tarafı düzelt. Sırf test
  geçsin diye beklentileri mevcut kaynaklara eşitleme veya kontrolleri kaldırma.
- Bölüm verisi değişirse o bölümlerde çözüm ve yıldız hedeflerini doğrula.
- Kayıtlı ilerleme ve bölüm kimliklerini koru; yeniden sıralama bu işin kapsamı
  değildir.

Kabul: ana oyun ve engel kontrolleri geçer; değişen bölümler çözülebilir.
İlgili araçlar: `check_blocks_and_gate.gd`, `check_obstacles.gd`,
`verify_levels.gd`.

## 2. Release canlı reklam geçişi

İlgili dosyalar: `scripts/monetization/luma_admob_config.gd`,
`scripts/monetization/providers/admob_ad_provider.gd`,
`addons/AdmobPlugin/android_export.cfg`, `tools/check_release_readiness.gd`,
`tools/check_monetization_phase2.gd` ve release belgeleri.

- Yorum satırlarında bulunan gerçek uygulama, ödüllü reklam ve geçiş reklamı
  kimliklerini release için etkinleştir.
- Canlı reklam seçimini hem `production` özelliğine hem debug olmayan build'e
  bağla. Debug build, production etiketi yanlışlıkla verilse bile demo kullanır.
- Export sırasında Android manifestine yazılan uygulama ID'siyle çalışma
  zamanındaki uygulama ve reklam birimi ID'lerini tutarlı hale getir.
- Provider'ın debug ve gerçek uygulama kimliklerine aynı değeri atamasını
  düzelt; yalnızca export cfg dosyasını değiştirmek yeterli değildir.
- Kapalı test döneminin `is_real=false` / demo ID zorunluluklarını yeni
  release-debug ayrımını doğrulayacak kontrollerle değiştir.
- Mevcut izin/UMP akışını, reklam sıklığını ve remove_ads davranışını koru.
- Reklam yüklenmemesi, bağlantı olmaması, erken kapanma ve yinelenen callback
  durumlarında oyunun devam etmesini; ödülün yalnızca geçerli ödül callback'iyle
  bir kez verilmesini test et.

Kabul: release AAB manifesti gerçek uygulama ID'sini taşır; runtime gerçek
birimleri seçer; debug APK demo kimlikleri taşır. İzin alınmadan reklam isteği
başlamaz. Canlı gösterim hesap durumu ve reklam doluluğuna da bağlıdır; build
başarısı tek başına canlı reklam teslimini kanıtlamaz.

Cihaz doğrulaması: aynı gerçek birimleri kayıtlı AdMob test cihazında test
reklamıyla kontrol et. Bu işlem release'in gerçek ID seçimini değiştirmez;
üretim trafiği üzerinde otomatik reklam tıklama testi yapılmaz.

## 3. İlk atışı etkileşimli öğret

İlgili dosyalar: yeni `scripts/ui/first_shot_tutorial.gd`, ilgili UI sahnesi,
`scripts/gameplay.gd`, `scripts/launcher.gd`, `scripts/app_root.gd`,
`scripts/levels/progress_store.gd`, `scripts/settings_screen.gd`,
`assets/i18n/ui.csv` ve `tools/check_startup_experience.gd`.

- İlk bölümde kısa akış: topa dokun, sürükleyerek nişan al, gücü değiştir,
  bırakarak at. Adımlar zamanlayıcıyla değil gerçek oyuncu girdisiyle ilerler.
- Parmağın altında kalmayan görsel işaretler ve kısa metinler kullan.
- İptal edilen nişan veya başarısız ilk atış öğreticiyi kilitlemez; oyuncu
  tekrar deneyebilir. Atla seçeneği her adımda erişilebilirdir.
- Tamamlama/atlama durumunu sürümlü bir kayıt alanında tut. Eski kayıtları
  taşırken mevcut oyuncuya zorunlu öğretici açma.
- Ayarlara 'Nasıl oynanır?' ekle; tekrar gösterme oyun ilerlemesini sıfırlamaz.
- Mevcut mekanik tanıtım kartlarıyla sırala; aynı anda iki modal açma.
- Öğretici sırasında geçiş reklamı ve review isteği gösterme.
- Ekran değişince sinyal bağlantılarını ve giriş kısıtlamalarını temizle.
  Ekran geçişlerini AppRoot yönetir.

Kabul: temiz kayıt, mevcut kayıt, atlama, tekrar açma, başarısız atış,
menüye dönüş ve yeniden başlatma akışları çalışır. Dokunmatik ve fare girdisi,
dikey/yatay ekran, tablet düzeni ve desteklenen diller kontrol edilir.

## 4. Oyun içi değerlendirme ve geri bildirim

Durum: kod, Android eklentisi, yerel testler ve debug APK paket doğrulaması
tamamlandı. Play dağıtımı üzerinden gerçek cihaz testi 5. adımda yapılacak.

İlk teslim: ayarlara 'Oyunu değerlendir' ve 'Geri bildirim gönder' seçenekleri.

- Değerlendirme düğmesi doğrudan uygulamanın Play Store sayfasını açar.
- Geri bildirim, kullanıcının görebileceği/düzenleyebileceği bir taslak açar;
  otomatik mesaj göndermez. Sürüm ve isteğe bağlı bölüm bilgisi eklenebilir;
  reklam kimliği, satın alma token'ı veya tam kayıt dosyası eklenmez.
- Destek adresi: `ofsgamesofficial@gmail.com`. Geri bildirim akışı bu adresi
  kullanacak; kullanıcı adına otomatik mesaj gönderilmeyecek.
- Dış bağlantı açma hatalarında anlaşılır geri bildirim ver. Gizlilik için
  kullanılan mevcut HTTPS korumasını e-posta desteği uğruna gevşetme; destek
  bağlantısını ayrı, açıkça izin verilen adreslerle işle.

İkinci teslim: `scripts/engagement/review_service.gd` ve Android review
provider/plugin entegrasyonu. Mevcut projede review eklentisi bulunmadı;
uygun entegrasyonun motorla uyumluluğu önce doğrulanacak.

- İlk taslak eşik: en az 5 farklı bölüm ve 2 oturumdan sonra, sonuç ekranından
  normal akışa dönerken bir istek; başarısızlık ekranında ve reklamın hemen
  ardından değil. Bu eşikler ürün tercihi olup ölçümlere göre değiştirilebilir.
- Son deneme zamanını kalıcı sakla; başlangıç bekleme aralığı 90 gün.
- Google'ın diyaloğu göstermediği veya API'nin hata verdiği durumda oyun
  akışını bekletme. API dönüşünü kullanıcının puan verdiği şeklinde kaydetme.
- Puan karşılığı ödül, olumlu yoruma yönlendirme veya ön eleme sorusu ekleme.
- Öğretici, reklam, satın alma, izin formu ve review aynı anda açılmasın.

Kabul: tekrar sıklığı ve uygunluk testleri; provider yokken güvenli devam;
Play test dağıtımı üzerinden gerçek cihaz doğrulaması. Destek adresinin açılması
test edilir, kullanıcı adına mesaj gönderilmez.

## 5. Erişilebilirlik ve son doğrulama

Durum: tamamlandı. Altı dil ve telefon/tablet/yatay yerleşimler otomatik ve
görsel olarak kontrol edildi; imzalı versionCode 9 AAB ile debug APK üretildi
ve paket/içerik/imza kontrolleri geçti. Mevcut seviye kaynakları değişmedi.

- Yeni UI öğeleri mevcut titreşim/ekran sarsıntısı tercihlerine uysun.
- Öğretici ve geri bildirim yalnızca renk veya sesle bilgi vermesin; metin,
  şekil ve görsel işaret birlikte kullanılsın.
- Metin taşması, kontrast, dokunma alanları ve dil değişimi kontrol edilsin.
- Yeni metinler `assets/i18n/ui.csv` içindeki mevcut dillere eklensin.
- Sosyal paylaşım ve kapsamlı topluluk özellikleri sonraki sürüme bırakılsın.

Son kontroller: headless açılış, `check_blocks_and_gate.gd`,
`check_obstacles.gd`, `check_startup_experience.gd`,
`check_monetization_phase2.gd`, `check_hint_economy.gd`,
`check_billing_phase7.gd`, `check_release_readiness.gd` ve değişen alanların
odaklı yeni kontrolleri. Bölüm değişirse `verify_levels.gd` de çalışır.

Teslim: imzalı release AAB + debug APK; imza, manifest ve paket içerik
doğrulaması; cihazda öğretici/reklam/geri bildirim akışı testi. Bir sonraki
release için versionCode artırılır; mağazaya yükleme yapılmaz.

## Kaynaklar

- Yerel testçi raporu: `com.ofsgames.lumabounce_feedback.pdf`.
- [AdMob test reklamları ve gerçek ID ile test cihazları](https://developers.google.com/admob/android/test-ads).
- [Google Play In-App Review](https://developer.android.com/guide/playcore/in-app-review).
- [Review entegrasyon testi](https://developer.android.com/guide/playcore/in-app-review/test).
