class_name MainMenu
extends Control

## Ana menu.
##
## Yerlesim tamamen anchor tabanlidir ve [SafeAreaMargin] icinde durur;
## boylece 720x1280 referansindan sapan ekran oranlarinda ve centikli
## cihazlarda da dogru konumlanir.
##
## OYNA kalinan bolumu acar, BOLUMLER bolum secim ekranini, dislisi de
## ayarlar ekranini acar.
##
## Ses butonu yerel bir bayrak TUTMAZ: tek dogruluk kaynagi AudioManager'dir.
## Ikon hem acilista hem de mute_changed sinyaliyle guncellenir, boylece
## durum baska bir ekrandan degisse bile senkron kalir ve uygulama yeniden
## acildiginda kayitli mute durumu korunur.
##
## Ekran hicbir sahneyi kendisi acmaz; yalnizca sinyal yayar.

signal play_pressed(level_id: int)
signal levels_requested()
signal settings_requested()

## AppRoot tarafindan add_child'dan ONCE atanir: kalinan bolum.
var resume_level_id := 1

## Kisa bilgi mesaji icin ayarlar. Su an menude bunu tetikleyen bir yol yok
## (ayarlar dislisi artik gercek ekrani aciyor); yapi ileride "kaydedildi",
## "internet yok" gibi anlik geri bildirimler icin duruyor.
@export var toast_visible_time := 1.2
@export var toast_fade_in := 0.18
@export var toast_fade_out := 0.32

@onready var _logo: LumaLogo = $SafeArea/Content/Logo
@onready var _play_button: LumaButton = $SafeArea/Content/PlayButton
@onready var _levels_button: LumaButton = $SafeArea/Content/LevelsButton
@onready var _sound_button: LumaIconButton = $SafeArea/Content/SoundButton
@onready var _settings_button: LumaIconButton = $SafeArea/Content/SettingsButton
@onready var _toast: Label = $SafeArea/Content/Toast

var _toast_tween: Tween


func _ready() -> void:
	_toast.hide()
	_toast.modulate.a = 0.0
	_logo.show_revealed()
	_refresh_sound_glyph()

	_play_button.pressed.connect(_on_play_pressed)
	_levels_button.pressed.connect(levels_requested.emit)
	_settings_button.pressed.connect(settings_requested.emit)
	_sound_button.pressed.connect(AudioManager.toggle_muted)
	AudioManager.mute_changed.connect(_on_mute_changed)


func _on_play_pressed() -> void:
	play_pressed.emit(resume_level_id)


func _on_mute_changed(_muted: bool) -> void:
	_refresh_sound_glyph()


func _refresh_sound_glyph() -> void:
	_sound_button.glyph = (GlyphIcon.Glyph.SOUND_OFF if AudioManager.is_muted()
		else GlyphIcon.Glyph.SOUND_ON)


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
