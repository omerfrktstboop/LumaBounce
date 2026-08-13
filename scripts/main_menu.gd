class_name MainMenu
extends Control

## Ana menu (FAZ 9 yeniden tasarimi).
##
## Yerlesim artik konteyner tabanlidir (Content bir VBoxContainer) - eskiden
## her dugum tek tek anchor/offset ile elle konumlaniyordu. [SafeAreaMargin]
## icinde durmaya devam eder; boylece 720x1280 referansindan sapan ekran
## oranlarinda ve centikli cihazlarda da dogru konumlanir.
##
## Yapi: Ust bar (marka + Coin rozeti + ayarlar) -> Hero oynanis karti ->
## OYNA -> Bolumler/Magaza navigasyon kartlari -> alt yardimci alan (ses +
## ilerleme ozeti). Marka rehberi SS31 geregi buyuk/tam-genislik logo
## KULLANILMAZ - marka kimligi kucuk bir LumaLogo ile ust barda temsil edilir.
##
## OYNA kalinan bolumu acar, BOLUMLER bolum secim ekranini, dislisi de
## ayarlar ekranini acar. Coin rozeti dokununca magazayi acar (VAR OLAN
## shop_requested sinyaliyle, yeni bir AppRoot kancasi gerekmedi).
##
## Ses butonu yerel bir bayrak TUTMAZ: tek dogruluk kaynagi AudioManager'dir.
## Ikon hem acilista hem de mute_changed sinyaliyle guncellenir, boylece
## durum baska bir ekrandan degisse bile senkron kalir ve uygulama yeniden
## acildiginda kayitli mute durumu korunur.
##
## Ekran hicbir sahneyi kendisi acmaz; yalnizca sinyal yayar.

signal play_pressed(level_id: int)
signal levels_requested()
signal shop_requested()
signal settings_requested()
signal daily_requested()

## AppRoot tarafindan add_child'dan ONCE atanir: kalinan bolum.
var resume_level_id := 1
## AppRoot tarafindan add_child'dan ONCE atanir: Coin rozeti ve ilerleme
## ozeti icin. Magaza/Ayarlar'in zaten yaptigi gibi ayni ORNEK enjekte edilir.
var wallet: WalletStore
var progress: ProgressStore
var daily_store: DailyStore

## Kisa bilgi mesaji icin ayarlar. Su an menude bunu tetikleyen bir yol yok
## (ayarlar dislisi artik gercek ekrani aciyor); yapi ileride "kaydedildi",
## "internet yok" gibi anlik geri bildirimler icin duruyor.
@export var toast_visible_time := 1.2
@export var toast_fade_in := 0.18
@export var toast_fade_out := 0.32

@onready var _brand_mark: LumaLogo = $SafeArea/Content/TopAppBar/BrandMark
@onready var _coin_chip: CoinChip = $SafeArea/Content/TopAppBar/CoinChip
@onready var _settings_button: LumaIconButton = $SafeArea/Content/TopAppBar/SettingsButton
@onready var _hero_card: PanelContainer = $SafeArea/Content/MainActions/HeroCard
@onready var _play_button: LumaButton = \
	$SafeArea/Content/MainActions/PrimaryActionMargin/PlayButton
@onready var _levels_card: NavigationCard = $SafeArea/Content/MainActions/LevelsCard
@onready var _shop_card: NavigationCard = $SafeArea/Content/MainActions/ShopCard
@onready var _sound_button: LumaIconButton = $SafeArea/Content/UtilityArea/SoundButton
@onready var _progress_label: Label = $SafeArea/Content/UtilityArea/ProgressLabel
@onready var _utility_area: HBoxContainer = $SafeArea/Content/UtilityArea
@onready var _toast: Label = $Toast

var _toast_tween: Tween


func _ready() -> void:
	_toast.hide()
	_toast.modulate.a = 0.0
	_brand_mark.show_revealed()
	_hero_card.add_theme_stylebox_override("panel", LumaCard.panel_style(
		UIMetrics.RADIUS_LARGE_CARD, Color(Palette.INK_MID, 0.78)))
	_refresh_sound_glyph()
	_refresh_progress_label()
	_build_daily_button()
	if wallet != null:
		_coin_chip.bind(wallet)

	_play_button.pressed.connect(_on_play_pressed)
	_levels_card.pressed.connect(levels_requested.emit)
	_shop_card.pressed.connect(shop_requested.emit)
	_settings_button.pressed.connect(settings_requested.emit)
	_coin_chip.pressed.connect(shop_requested.emit)
	_sound_button.pressed.connect(AudioManager.toggle_muted)
	AudioManager.mute_changed.connect(_on_mute_changed)


## Ana menu zaten dolu bir dikey hiyerarsiye sahip. Daily erisimini ucuncu
## buyuk NavigationCard olarak eklemek kisa telefonlarda tasma yaratirdi;
## alt utility satirindaki 72 birimlik kompakt buton ayni isi yapar.
func _build_daily_button() -> void:
	var button := LumaButton.new()
	button.name = "DailyButton"
	button.custom_minimum_size = Vector2(210.0, UIMetrics.MIN_TOUCH)
	button.emphasis = LumaButton.Emphasis.SECONDARY
	button.add_theme_font_size_override("font_size", UIMetrics.FONT_BODY + 1)
	# Gorevler 8'de, challenge 10'da acilir. Oyuncu 8'den itibaren ekrana
	# girebilmeli; challenge karti kendi kilidini ayrica gosterir.
	var unlocked := progress != null and progress.is_completed(DailyStore.QUESTS_UNLOCK_LEVEL)
	var claimed := daily_store != null and daily_store.is_daily_claimed()
	button.text = tr("GÜNLÜK ✓") if claimed else tr("GÜNLÜK")
	button.disabled = not unlocked
	button.tooltip_text = tr("8. bölümü tamamlayınca açılır") if not unlocked else tr("Günlük challenge ve görevler")
	button.pressed.connect(daily_requested.emit)
	_utility_area.add_child(button)
	_utility_area.move_child(button, _progress_label.get_index())


func _on_play_pressed() -> void:
	play_pressed.emit(resume_level_id)


func _on_mute_changed(_muted: bool) -> void:
	_refresh_sound_glyph()


func _refresh_sound_glyph() -> void:
	_sound_button.glyph = (GlyphIcon.Glyph.SOUND_OFF if AudioManager.is_muted()
		else GlyphIcon.Glyph.SOUND_ON)


## "N / M yıldız": ilerlemeyi tek bir sayida ozetler. Bolum numarasi yerine
## yildiz kullanilir cunku bonus bolumler numara sirasini anlamsizlastirir
## (bkz. LevelWorlds), oysa toplam yildiz her zaman dogrusal ilerler.
func _refresh_progress_label() -> void:
	if progress == null:
		_progress_label.hide()
		return
	_progress_label.text = tr("%d / %d yıldız") % [
		progress.get_total_stars(), progress.get_max_available_stars()]


## Kisa, sade bilgi mesaji. Ayri bir pencere/diyalog acmaz.
func _show_toast(text: String) -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()

	_toast.text = text
	_toast.modulate.a = 0.0
	_toast.show()

	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, toast_fade_in)
	_toast_tween.tween_interval(toast_visible_time)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, toast_fade_out)
	_toast_tween.tween_callback(_toast.hide)
