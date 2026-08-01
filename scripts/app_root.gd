class_name AppRoot
extends Node

## Uygulamanin giris noktasi: splash -> ana menu -> bolum secimi -> oynanis.
##
## MIMARI KURAL: ekranlar birbirini asla instantiate etmez. Her ekran yalnizca
## sinyal yayar, tum gecis ve ilerleme kararlari burada verilir. Ekranlara
## ihtiyac duyduklari veri (bolum, ilerleme, playtest istatistikleri) add_child'dan
## ONCE enjekte edilir, boylece _ready icinde hazir olur.
##
## Ekranlar ScreenHost altina tek tek yuklenir; her gecis kisa bir fade ile
## ortulur. Fade rengi saf siyah degil, paletin en koyu murekkep tonudur.
##
## Uygulama arka plana gecince (odak kaybi / OS duraklatmasi) tum sahne
## agacini duraklatir: bu hem "guvenli duraklama" hem de "topun ani fizik
## sicramasi" sorununu tek mekanizmayla cozer - fizik/animasyon islenmedigi
## icin geri donuste birikmis bir "yakalama" adimi olmaz, kaldigi yerden
## normal bir fizik adimiyla devam eder.

@export var splash_scene: PackedScene
@export var main_menu_scene: PackedScene
@export var level_select_scene: PackedScene
@export var gameplay_scene: PackedScene
## Yalnizca debug build'de acilir (bkz. _on_debug_editor_requested); release
## export'ta debug paneli var olmadigi icin bu ekrana giden yol yoktur.
@export var level_editor_scene: PackedScene
@export var fade_time := 0.28
@export var fade_color := Palette.INK_TOP

@onready var _host: Node = $ScreenHost
@onready var _fade: ColorRect = $FadeLayer/Fade
@onready var _debug_panel: DebugPanel = $DebugLayer/DebugPanel

var _progress: ProgressStore
var _playtest_stats: PlaytestStats
## Debug paneli disinda hicbir yerde okunmaz; gercek save'e asla yazilmaz.
var _debug_unlock_all := false
var _current: Node
## Son go_to_level cagrisinda istenen bolum. Debug onceki/sonraki/tekrar
## butonlari icin tutulur.
var _current_level_id := LevelLibrary.FIRST_LEVEL_ID
## Editorden test edilen bolum. Oynanistan cikildiginda editore ayni veriyle
## donebilmek icin tutulur; kaydedilmemis duzenleme kaybolmaz.
var _editor_level: LevelData
var _busy := false


func _ready() -> void:
	# process_mode = ALWAYS (sahnede ayarli): uygulama arka plana alinsa/odagi
	# kaybetse bile bu dugum calismaya devam etmeli ki duraklatma/devam
	# bildirimlerini kacirmasin.
	_progress = ProgressStore.load_from_disk()
	_playtest_stats = PlaytestStats.load_from_disk()
	_connect_debug_panel()

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


## Telefonun geri tusu VE uygulama odak/arka plan bildirimleri.
## quit_on_go_back kapali oldugu icin geri tusunda uygulama kendiliginden
## kapanmaz; hiyerarside bir adim geri gideriz.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_handle_go_back()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_set_application_paused(true)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_set_application_paused(false)


func _set_application_paused(paused: bool) -> void:
	if get_tree().paused == paused:
		return
	var gameplay := _current as Gameplay
	if gameplay != null:
		gameplay.set_app_paused(paused)
	get_tree().paused = paused


# --- Ekran gecisleri ---------------------------------------------------------

func go_to_main_menu() -> void:
	await _transition(main_menu_scene, _configure_main_menu)


func go_to_level_select() -> void:
	await _transition(level_select_scene, _configure_level_select)


func go_to_level(level_id: int) -> void:
	_current_level_id = LevelLibrary.clamp_id(level_id)
	await _transition(gameplay_scene, _configure_gameplay.bind(_current_level_id))


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

	if _debug_panel != null and is_instance_valid(_debug_panel) and not _debug_panel.is_queued_for_deletion():
		_debug_panel.set_active_gameplay(instance as Gameplay)


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
		# Editorden test edildiyse "menu" tusu editore geri doner; yoksa
		# tasarladigin bolumu terk etmek icin tek yol kaydetmek olurdu.
		gameplay.menu_requested.connect(_on_gameplay_menu_requested)
		return

	var editor := screen as LevelEditor
	if editor != null:
		editor.test_requested.connect(_on_editor_test_requested)
		editor.menu_requested.connect(_on_editor_closed)


func _configure_main_menu(screen: Node) -> void:
	var menu := screen as MainMenu
	if menu != null:
		menu.resume_level_id = _progress.get_resume_level_id()


func _configure_level_select(screen: Node) -> void:
	var select := screen as LevelSelect
	if select != null:
		select.progress = _progress
		select.debug_force_unlock = _debug_unlock_all


func _configure_gameplay(screen: Node, level_id: int) -> void:
	var gameplay := screen as Gameplay
	if gameplay != null:
		gameplay.level_data = LevelLibrary.load_level(level_id)
		gameplay.playtest_stats = _playtest_stats
		gameplay.progress = _progress


## Kazanilan yildiz yalnizca oncekinden IYIYSE kaydedilir; eski 3, yeni 1
## ise kayit 3 kalir (bkz. ProgressStore.set_level_stars_if_higher).
func _on_level_completed(level_id: int, stars: int) -> void:
	# Editorden test edilen bolum gercek ilerlemeye YAZILMAZ; henuz oyunun
	# bir parcasi degil ve kaydi kirletmesi anlamsiz olurdu.
	if _editor_level != null:
		return
	_progress.mark_completed(level_id)
	_progress.set_level_stars_if_higher(level_id, stars)


func _on_gameplay_menu_requested() -> void:
	if _editor_level != null:
		go_to_editor(_editor_level)
		return
	go_to_main_menu()


# --- Bolum editoru (yalnizca debug) -------------------------------------------
#
# Ayri bir "admin" yapisi yok: bu ekrana giden tek yol debug panelidir, o da
# release export'ta kendini agactan siler. Editor ekrani release APK'da
# bulunur ama ulasilamaz.

func go_to_editor(edit_level: LevelData = null) -> void:
	_editor_level = edit_level
	await _transition(level_editor_scene, _configure_editor)


func _configure_editor(screen: Node) -> void:
	var editor := screen as LevelEditor
	if editor != null and _editor_level != null:
		editor.level = _editor_level


## Editordeki bolumu oynatir. Kopya DEGIL ayni kaynak verilir: test sirasinda
## bolum degismez, ve geri donuldugunde duzenleme aynen durur.
func _on_editor_test_requested(edit_level: LevelData) -> void:
	_editor_level = edit_level
	await _transition(gameplay_scene, _configure_editor_gameplay)


func _configure_editor_gameplay(screen: Node) -> void:
	var gameplay := screen as Gameplay
	if gameplay != null:
		gameplay.level_data = _editor_level
		gameplay.playtest_stats = _playtest_stats
		gameplay.progress = _progress


func _on_editor_closed() -> void:
	_editor_level = null
	go_to_main_menu()


# --- Geri tusu ---------------------------------------------------------------

func _handle_go_back() -> void:
	if _busy:
		return

	var splash := _current as SplashScreen
	if splash != null:
		splash.skip()
		return

	var editor := _current as LevelEditor
	if editor != null:
		_on_editor_closed()
		return

	var gameplay := _current as Gameplay
	if gameplay != null:
		# Editorden test ediliyorsa geri tusu de editore doner.
		if _editor_level != null:
			go_to_editor(_editor_level)
		else:
			go_to_level_select()
		return

	var select := _current as LevelSelect
	if select != null:
		go_to_main_menu()
		return

	# Ana menude geri tusu uygulamadan cikar.
	get_tree().quit()


# --- Debug paneli -------------------------------------------------------------
#
# Panel sadece debug build'de var olur (bkz. debug_panel.gd _ready). Release
# export'ta $DebugLayer/DebugPanel kendini agactan kaldirdigi icin bu
# baglantilar kurulamaz ama zararsizdir; _debug_panel null/gecersiz kalir.

func _connect_debug_panel() -> void:
	if _debug_panel == null or not is_instance_valid(_debug_panel) or _debug_panel.is_queued_for_deletion():
		return
	_debug_panel.previous_level_requested.connect(_on_debug_previous_level)
	_debug_panel.next_level_requested.connect(_on_debug_next_level)
	_debug_panel.restart_level_requested.connect(_on_debug_restart_level)
	_debug_panel.unlock_all_toggled.connect(_on_debug_unlock_all_toggled)
	_debug_panel.reset_stats_requested.connect(_on_debug_reset_stats)
	_debug_panel.editor_requested.connect(_on_debug_editor_requested)


func _on_debug_previous_level() -> void:
	if _current is Gameplay:
		go_to_level(_current_level_id - 1)


func _on_debug_next_level() -> void:
	if _current is Gameplay:
		go_to_level(_current_level_id + 1)


func _on_debug_restart_level() -> void:
	var gameplay := _current as Gameplay
	if gameplay != null:
		gameplay.reset_shot()


## Yalnizca oturum-ici bir bayrak degistirir; ProgressStore'a hic dokunmaz,
## bu yuzden gercek save dosyasi kalici olarak etkilenmez.
func _on_debug_unlock_all_toggled(enabled: bool) -> void:
	_debug_unlock_all = enabled
	var select := _current as LevelSelect
	if select != null:
		select.set_debug_force_unlock(enabled)


func _on_debug_reset_stats() -> void:
	if _playtest_stats != null:
		_playtest_stats.reset_all()


func _on_debug_editor_requested() -> void:
	if _current is LevelEditor:
		return
	# Bos bolumle acilir; editordeki "AC" ile kayitli bir bolum yuklenebilir.
	go_to_editor()
