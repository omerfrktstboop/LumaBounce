class_name AppRoot
extends Node

## Uygulamanin giris noktasi: splash -> ana menu -> oynanis akisini yonetir.
##
## Ekranlar ScreenHost altina tek tek yuklenir; her gecis kisa bir fade ile
## ortulur. Fade rengi saf siyah degil, paletin en koyu murekkep tonudur -
## boylece gecisler de ayni gorsel kimlik icinde kalir.
##
## gameplay.tscn hicbir sekilde degistirilmeden, oldugu gibi yuklenir.

@export var splash_scene: PackedScene
@export var main_menu_scene: PackedScene
@export var gameplay_scene: PackedScene
@export var fade_time := 0.28
@export var fade_color := Palette.INK_TOP

@onready var _host: Node = $ScreenHost
@onready var _fade: ColorRect = $FadeLayer/Fade

var _current: Node
var _busy := false


func _ready() -> void:
	# Ilk ekran bilerek fade'siz acilir: splash'in kendi top-dususu zaten
	# acilis animasyonudur, onune bir fade koymak sekme anini gizlerdi.
	# Fade yalnizca ekranlar ARASI gecislerde kullanilir.
	_fade.color = Color(fade_color, 0.0)
	_fade.visible = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swap_to(splash_scene)


## Gecis sirasinda hicbir girdi alttaki ekrana ulasmasin.
## (Control'lar dokunma olaylarini yutmadigi icin sadece fade'in
## mouse_filter'ina guvenmek yeterli olmaz.)
func _input(_event: InputEvent) -> void:
	if _busy:
		get_viewport().set_input_as_handled()


# --- Ekran gecisleri ---------------------------------------------------------

func go_to_main_menu() -> void:
	await _transition(main_menu_scene)


func go_to_gameplay() -> void:
	await _transition(gameplay_scene)


func _transition(scene: PackedScene) -> void:
	if _busy or scene == null:
		return
	_busy = true
	await _fade_to(1.0)
	_swap_to(scene)
	await _fade_to(0.0)
	_busy = false


func _fade_to(alpha: float) -> void:
	_fade.visible = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, fade_time)
	await tween.finished
	if is_zero_approx(alpha):
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.visible = false


func _swap_to(scene: PackedScene) -> void:
	if scene == null:
		push_warning("AppRoot: yuklenecek sahne atanmamis.")
		return

	if _current != null:
		# queue_free tek basina yetmez: dugum kare sonuna kadar agacta kalir
		# ve yeni ekranla birlikte cizilip islenirdi.
		_host.remove_child(_current)
		_current.queue_free()
		_current = null

	var instance := scene.instantiate()
	_host.add_child(instance)
	_current = instance
	_connect_screen(instance)


func _connect_screen(screen: Node) -> void:
	var splash := screen as SplashScreen
	if splash != null:
		splash.finished.connect(go_to_main_menu)
		return

	var menu := screen as MainMenu
	if menu != null:
		menu.play_pressed.connect(go_to_gameplay)
