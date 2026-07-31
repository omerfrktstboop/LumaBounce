class_name Palette
extends RefCounted

## LumaBounce tema paleti. Tum renkler tek yerden yonetilir.
##
## TASARIM KURALI - "tek vurgu":
## Sahnenin buyuk cogunlugu sessizdir (ink zemin + surface yuzeyler).
## Neon vurgu YALNIZCA oyuncunun odaklanmasi gereken uc elemanda kullanilir:
##   1) top   2) nisan kilavuzu   3) hedef
## Ikincil vurgu (menekse) sadece isabet / basari aninda gorunur.


# --- Zemin: derin murekkep lacivert (saf siyah degil) ---
const INK_TOP := Color("17233a")
const INK_MID := Color("1e2d46")
const INK_BOTTOM := Color("22324d")

# --- Sessiz yuzeyler: duvar, panel, firlatici ---
const SURFACE := Color("2b3c5b")
const SURFACE_EDGE := Color("3a4f76")
const SURFACE_LIGHT := Color("4d6595")
const FRAME := Color("31446a")
## Sekme paneli govdesi: SURFACE'tan ~%10 daha acik. Panellerin zeminden
## net ayrismasi icin ayri tutulur (SURFACE duvar/buton/firlaticida da
## kullanildigi icin onu genel olarak aydinlatmak tum arayuzu degistirirdi).
const SURFACE_PANEL := Color("40506b")

# --- Kirilabilir blok yuzeyi ---
# Panelden AYIRT EDILEBILIR olmali ama neon top/hedefle yarismamali.
# Panel "saglam" hissi verir (acik mat govde, yuvarlak stadyum); blok ise
# "modulup kirilabilir" hissi verir: daha KOYU govde, daha PARLAK ince kenar
# ve merkezdeki dikis cizgisi. Tonlar bilerek cyan/teal DEGIL, mavi-gri.
const SURFACE_BLOCK := Color("32405c")
const SURFACE_BLOCK_EDGE := Color("6d86b6")
## Merkezdeki hafif kirilma/segment cizgisi.
const SURFACE_BLOCK_SEAM := Color("8ba3ce")

# --- Birincil vurgu: neon camgobegi / teal ---
const ACCENT := Color("34e6d4")
const ACCENT_DIM := Color("1ba99d")
const ACCENT_CORE := Color("ecfffc")

# --- Ikincil vurgu: yumusak menekse (isabet ve basari) ---
const ACCENT_ALT := Color("c07dff")
const ACCENT_ALT_CORE := Color("f6ecff")

# --- Metin ---
const TEXT := Color("e9f2ff")
const TEXT_DIM := Color("93a7c9")
