class_name GameVersion
extends RefCounted

## Surum bilgisinin TEK kaynagi.
##
## Uc surum numarasi BILEREK ayridir; farkli hizlarda ve farkli sebeplerle
## degisirler, tek bir numaraya baglamak ucunu de yanlis yonetmek olurdu:
##
##   GAME       - magazaya gonderilen oyun surumu (semver). Her yayinda artar.
##   SAVE_SCHEMA- kayit DOSYASININ yapisi. Yalnizca kayit alanlari degisince
##                artar ve ProgressStore migration'i buna bakar. Oyun 20 kez
##                guncellense de kayit yapisi degismediyse bu 1 kalir.
##   CONTENT    - bolum/icerik paketi surumu. Yeni bolumler eklendiginde artar;
##                kayit yapisini etkilemez.
##
## ANDROID NOTU: buradaki GAME degeri export_presets.cfg'deki version/name ile
## ELLE eslenmelidir; Godot bunu otomatik okumaz. version/code (versionCode)
## ise HER Play Store yuklemesinde artmak ZORUNDADIR, aksi halde magaza
## paketi reddeder (bkz. docs/RELEASE.md).

const GAME := "1.0.0"
## 2: [settings] bolumune dil, ekran sarsintisi ve nisan yardimi eklendi.
## v1 -> v2 icin VERI DONUSUMU GEREKMEZ; yeni alanlarin hepsi savunmaci
## okunur ve makul bir varsayilana duser (dil bos = cihaz dili). Numara yine
## de artirildi, cunku surumun anlami "bu kaydi hangi alan kumesini bilen
## surum yazdi" - eski bir surum yeni kaydi actiginda bunu gorebilmeli.
const SAVE_SCHEMA := 2
const CONTENT := 1


## "1.0.0 (icerik 1)" - hata raporlarinda ve debug panelinde gosterilir.
static func describe() -> String:
	return "%s (icerik %d, kayit sema %d)" % [GAME, CONTENT, SAVE_SCHEMA]
