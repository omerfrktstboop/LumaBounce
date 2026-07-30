class_name AppRoot
extends Node

## Uygulamanin giris noktasi: splash -> ana menu -> bolum secimi -> oynanis.
##
## MIMARI KURAL: ekranlar birbirini asla instantiate etmez. Her ekran yalnizca
## sinyal yayar, tum gecis ve ilerleme kararlari burada verilir. Ekranlara
## ihtiyac duyduklari veri (bolum, ilerleme) add_child'dan ONCE enjekte edilir,
## boylece _ready icinde hazir olur.
##
## Ekranlar ScreenHost altina tek tek yuklenir; her gecis kisa bir fade ile
## ortulur. Fade rengi saf siyah degil, paletin en koyu murekkep tonudur.

@export var splash_scene: PackedScene
@export var main_menu_scene: PackedScene
@export var level_select_scene: PackedScene
@export var gameplay_scene: PackedScene
@export var fade_time := 0.28
@export var fade_color := Palette.INK_TOP

@onready var _host: Node = $ScreenHost
@onready var _fade: ColorRect = $FadeLayer/Fade

var _progress: ProgressStore
var _current: Node
var _busy := false


func _ready() -> void:
	_progress = ProgressStore.load_from_disk()
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


## Telefonun geri tusu. project.godot'ta quit_on_go_back kapali oldugu icin
## uygulama kendiliginden kapanmaz; hiyerarside bir adim geri gideriz.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_go_back()


# --- Ekran gecisleri ---------------------------------------------------------

func go_to_main_menu() -> void:
	await _transition(main_menu_scene, _configure_main_menu)


func go_to_level_select() -> void:
	await _transition(level_select_scene, _configure_level_select)


func go_to_level(level_id: int) -> void:
	await _transition(gameplay_scene, _configure_gameplay.bind(level_id))


func _transition(scene: PackedScene, configure: Callable) -> void:
	if _busy or scene == null:
		return
	_busy = true
	await _fade_to(1.0)
	_swap_to(scene, configure)
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


func _swap_to(scene: PackedScene, configure := Callable()) -> void:
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
	# Sinyaller ve veri _ready'den once hazir olsun.
	_connect_screen(instance)
	if configure.is_valid():
		configure.call(instance)
	_host.add_child(instance)
	_current = instance


# --- Ekran kurulumu ----------------------------------------------------------

func _connect_screen(screen: Node) -> void:
	var splash := screen as SplashScreen
	if splash != null:
		splash.finished.connect(go_to_main_menu)
		return

	var menu := screen as MainMenu
	if menu != null:
		menu.play_pressed.connect(go_to_level)
		menu.levels_requested.connect(go_to_level_select)
		return

	var select := screen as LevelSelect
	if select != null:
		select.level_selected.connect(go_to_level)
		select.menu_requested.connect(go_to_main_menu)
		return

	var gameplay := screen as Gameplay
	if gameplay != null:
		gameplay.level_completed.connect(_on_level_completed)
		gameplay.next_level_requested.connect(go_to_level)
		gameplay.level_select_requested.connect(go_to_level_select)
		gameplay.menu_requested.connect(go_to_main_menu)


func _configure_main_menu(screen: Node) -> void:
	var menu := screen as MainMenu
	if menu != null:
		menu.resume_level_id = _progress.highest_unlocked_level


func _configure_level_select(screen: Node) -> void:
	var select := screen as LevelSelect
	if select != null:
		select.progress = _progress


func _configure_gameplay(screen: Node, level_id: int) -> void:
	var gameplay := screen as Gameplay
	if gameplay != null:
		gameplay.level_data = LevelLibrary.load_level(level_id)


func _on_level_completed(level_id: int) -> void:
	_progress.mark_completed(level_id)


# --- Geri tusu ---------------------------------------------------------------

func _handle_go_back() -> void:
	if _busy:
		return

	var splash := _current as SplashScreen
	if splash != null:
		splash.skip()
		return

	var gameplay := _current as Gameplay
	if gameplay != null:
		go_to_level_select()
		return

	var select := _current as LevelSelect
	if select != null:
		go_to_main_menu()
		return

	# Ana menude geri tusu uygulamadan cikar.
	get_tree().quit()
