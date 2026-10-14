# Bu bilgisayarda Android build

Proje kökünde PowerShell ile:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\build_android.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\build_android.ps1 -Configuration Debug
```

İlk komut imzalı release AAB, ikinci komut debug APK üretir. Çıktılar `builds/`
altına tarih/saat içeren adlarla yazılır. `-OutputPath` ile farklı bir yol
verilebilir; var olan çıktıların üzerine yazılmaz. ExecutionPolicy yalnızca
bu PowerShell işlemi için geçerlidir; sistem ayarı değiştirilmez.

## Yerel kurulum

- Godot: proje klasörünün yanındaki `Godot_v4.7.2-stable_win64_console.exe`.
  Farklı konum için `-GodotPath` kullanılabilir.
- Android SDK: `D:\DevTools\android-sdk`.
- JDK 17: `D:\DevTools\jdk17` altındaki Temurin kurulumu.
- Gradle önbelleği: `D:\DevTools\gradle-home`.
- Android export şablonları: `%APPDATA%\Godot\export_templates\4.7.2.stable`.
- Proje Android build şablonu: `android/build`, sürüm `4.7.2.stable`.
- Kurulum öncesi ayar ve şablon yedekleri:
  `D:\DevTools\godot-android-setup-backup`.

Godot Editor Settings içinde Android SDK ve Java SDK yolları da ayarlıdır.

## İmzalama

Release anahtarı `D:\LumaBounceSecrets\lumabounce-release.jks` dosyasındadır.
Build komutu aynı dizindeki `signing-current-user.clixml` dosyasından Windows
kullanıcı hesabıyla şifrelenmiş alias/parola bilgisini okur. Bu dosya yalnızca
onu oluşturan Windows kullanıcısı ve bilgisayarda açılabilir; taşınabilir bir
keystore yedeği değildir. Asıl keystore ve mevcut parola kaydını koruyun.

Parola yalnızca build işleminin ortamına aktarılır; işlem tamamlanınca önceki
ortam değerleri geri yüklenir. `export_presets.cfg` içindeki release imzalama
alanları bilerek boştur. Godot'u normal açarak GUI üzerinden release export
yapmak bu bilgileri otomatik yüklemez; yukarıdaki komutu kullanın.

Build komutu versionCode değerini değiştirmez. Google Play'e daha önce yüklenen
bir versionCode tekrar kullanılamaz; yeni yüklemeden önce `Android Release`
profilindeki `version/code` değerini artırın.

AdMob ayarları kapalı test kimliklerini kullanmaya devam eder. Build başarısı,
cihaz testi veya Play Console yayın onayı anlamına gelmez.

## Kurulum doğrulaması — 14 Eylül 2026

- Headless açılış ve `check_release_readiness.gd` geçti.
- Release AAB üretildi; JAR imzası doğrulandı ve imzalayan sertifika mevcut
  keystore ile eşleşti. Geliştirme araçları release paketinde bulunmadı.
- Debug APK üretildi; `apksigner verify` ve `zipalign -c -P 16 4` geçti.
  Bu ZIP hizalama kontrolüdür; fiziksel cihazda 16 KB çalışma testi yapılmadı.
  Build komutu Gradle arka plan sürecinde takılmadan başarıyla sonlandı.
- `check_blocks_and_gate.gd`: 1534 kontrol geçti, 39 kontrol başarısız.
  Hatalar 118, 126–136, 138–140 ve 148–150. bölümlerin blok/lazer beklentileriyle
  ilgilidir. Oyun kodu, bölüm kaynakları ve bu testler kurulum sırasında
  değiştirilmedi. Detaylı yerel çıktı: `scratchpad/android-setup-blocks-check.log`.
- Editor MCP eklentisi PATH üzerinde Node.js bulamadığını bildiriyor; Android
  export işlemini engellemedi. Android Gradle Plugin 8.6.1 ayrıca API 36 için
  sürüm desteği uyarısı veriyor; motorun sağladığı Gradle yapılandırması korundu.
