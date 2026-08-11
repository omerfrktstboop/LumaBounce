class_name CosmeticApplier
extends RefCounted

## Secili kozmetikleri oynanis dugumlerine uygular.
##
## TEK YER OLMASININ SEBEBI: "kozmetik fizige dokunmaz" sozu ancak uygulama
## noktasi TEK ise denetlenebilir. Renkler gameplay.gd'nin icine dagilsaydi
## birinin yanlislikla `ball.bounciness` yazmasi kimsenin dikkatini cekmezdi.
## Burasi yalnizca GORUNUM alanlarina yazar ve check_cosmetics.gd bu dosyanin
## fizik alani adlarina hic dokunmadigini metin olarak da dogrular.
##
## Dokunulan alanlar (hepsi ilgili sinifin "Gorunum"/"Iz" grubunda):
##   Ball     : accent, core_color, trail_accent, trail_length, trail_width_scale
##   Launcher : accent, accent_core
##   Target   : accent, core_color, success_color, glow_scale
##
## Dokunulmayanlar (fizik): radius, gravity, bounciness, max_speed,
## min_separation_speed, settle_speed, settle_time, max_bounces_per_step.

## Izin varsayilan uzunlugu; carpan buna uygulanir. Ball'un kendi
## varsayilanindan okunur ki iki yerde ayri sayi tutulmasin.
const BASE_TRAIL_LENGTH := 12
const BASE_TRAIL_WIDTH_SCALE := 0.85


## [param wallet] null ise hicbir sey yapilmaz - kozmetik yoksa oyun bugunku
## gorunumuyle calisir.
static func apply(wallet: WalletStore, ball: Ball, launcher: Launcher,
		target: Target) -> void:
	if wallet == null:
		return
	_apply_ball(wallet, ball)
	_apply_trail(wallet, ball)
	_apply_launcher(wallet, launcher)
	_apply_target(wallet, target)


static func _apply_ball(wallet: WalletStore, ball: Ball) -> void:
	if ball == null:
		return
	var item := wallet.selected_cosmetic(CosmeticData.Kind.BALL)
	if item == null:
		return
	ball.accent = item.accent
	ball.core_color = item.core
	if item.glow_scale > 0.0:
		ball.glow_scale = item.glow_scale
	ball._build_visual()


static func _apply_trail(wallet: WalletStore, ball: Ball) -> void:
	if ball == null:
		return
	var item := wallet.selected_cosmetic(CosmeticData.Kind.TRAIL)
	if item == null:
		return
	ball.trail_accent = item.accent
	# Uzunluk ve genislik GORSEL carpanlardir; iz fizige hic katilmaz
	# (bkz. ball.gd - _update_trail_response yalnizca cizim alanlarina yazar).
	ball.trail_length = maxi(int(round(float(BASE_TRAIL_LENGTH) * item.trail_length_scale)), 2)
	ball.trail_width_scale = clampf(
		BASE_TRAIL_WIDTH_SCALE * item.trail_width_scale, 0.4, 1.2)
	ball._setup_trail()


static func _apply_launcher(wallet: WalletStore, launcher: Launcher) -> void:
	if launcher == null:
		return
	var item := wallet.selected_cosmetic(CosmeticData.Kind.LAUNCHER)
	if item == null:
		return
	launcher.accent = item.accent
	launcher.accent_core = item.core
	launcher._build_base()
	launcher._build_barrel()
	launcher._build_power_meter()
	launcher._build_drag_hint()


static func _apply_target(wallet: WalletStore, target: Target) -> void:
	if target == null:
		return
	var item := wallet.selected_cosmetic(CosmeticData.Kind.TARGET_FX)
	if item == null:
		return
	target.accent = item.accent
	target.core_color = item.core
	target.success_color = item.alt
	if item.glow_scale > 0.0:
		target.glow_scale = item.glow_scale
	target._build_visual()
