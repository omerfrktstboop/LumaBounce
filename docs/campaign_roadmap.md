# LumaBounce 100 Bolum Yol Haritasi

Bu belge kampanya temposunu tanimlar. Mevcut 25 bolumun sirasi ve oyun
mekanikleri bu degisiklikle tasinmaz; yeni engeller kendi prototip ve fizik
dogrulama calismalari tamamlandiginda eklenir.

## Donemler

| Bolumler | Yeni odak | Uretim sablonu |
| --- | --- | --- |
| 1-25 | Temel firlatma, panel, kenar ve duvar boslugu ustaligi | Mevcut sablonlar, Sekme Zinciri |
| 26-50 | Kirilabilir tuglalar ve atislar arasinda kalici koridor acma | Blok Koridoru |
| 51-75 | Yeni engel A; hareketli engel prototipi ve okunabilir zamanlama | Tasarim/prototip kapisi |
| 76-99 | Yeni engel B; tek yonlu veya zirhli engel prototipi | Tasarim/prototip kapisi |
| 100 | Onceki donemleri birlestiren final ve final engeli | Ayri final dogrulamasi |

## Kilometre Tasi Kurali

- Her 25 bolumluk donemde yalnizca bir ana yeni fikir tanitilir.
- Yeni fikir ilk bes bolumde ogretilir, sonraki bolumlerde eski mekaniklerle
  birlestirilir ve donem sonunda ustalik bolumuyle kapanir.
- Kirilabilir tugla bolumleri 25'ten sonra, Bolum 26 ile baslar.
- Hareketli, tek yonlu, zirhli veya final engelleri bu planda kodlanmis kabul
  edilmez. Her biri eklenmeden once kontrol, mobil performans ve LevelSolver
  sozlesmesi ayrica belirlenir.
- Yeni donem eklenirken onceki donemlerin bolum koordinatlari ve fizigi geriye
  donuk olarak degistirilmez.

## Solver Kabul Hedefleri

- Sekme Zinciri: ana rota 5-10 sekme; saglam 0-4 sekmeli kestirme yok.
- Blok Koridoru: hedefe saglam rota 2-4 atista ve en az bir blok kirildiktan
  sonra acilir; ilk durumda saglam dogrudan rota yoktur.
- Yeni engel A/B/final: engel uygulamasiyla birlikte ayri durum modeli ve
  headless regresyon senaryosu eklenmeden kampanya uretiminde kullanilmaz.
