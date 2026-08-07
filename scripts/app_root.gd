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
@export var settings_scene: PackedScene
@export var gameplay_scene: PackedScene
## Yalnizca debug build'de acilir (bkz. _on_debug_editor_requested); release
## export'ta debug paneli var olmadigi icin bu ekrana giden yol yoktur.
@export var level_editor_scene: PackedScene
@export var fade_time := 0.28
@export var fade_color := Palette.INK_TOP
## Arka katman, arenanin murekkep tonundan bu kadar koyu olur (bkz.
## _apply_background_theme). Ayni tonda olsa derinlik hissi kaybolurdu.
@export_range(0.0, 1.0, 0.01) var background_darken := 0.35

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
## Uretilen veya kaydedilen parti, acik indeks ve metadata. Test sahnesi
## LevelEditor'u yok ettigi icin bu baglam AppRoot'ta yasatilir.
var _editor_batch_context := {}
## Editorde duzenlenen sey bir resmi bolumden geldiyse onun numarasi, yoksa 0.
var _editor_source_level_id := 0
var _busy := false


func _ready() -> void:
	# process_mode = ALWAYS (sahnede ayarli): uygulama arka plana alinsa/odagi
	# kaybetse bile bu dugum calismaya devam etmeli ki duraklatma/devam
	# bildirimlerini kacirmasin.
	_progress = ProgressStore.load_from_disk()
	# Titresim tercihi tek okuma noktasina (Haptics) aktarilir; boylece
	# cagiranlarin ProgressStore'a erisimi olmasi gerekmez (bkz. haptics.gd).
	Haptics.enabled = _progress.haptics_enabled
	# Dil ILK ekrandan once uygulanmali: bir Control'un metni cevrilirken
	# o anki locale okunur, sonradan degistirmek zaten kurulmus etiketleri
	# guncellemez. Kayitli tercih bos ise (oyuncu henuz secmedi) cihaz dili
	# kullanilir ve HICBIR SEY kaydedilmez - bkz. Locale.apply_saved.
	Locale.apply_saved(_progress.language)
	# Sarsinti tercihi de tek kisma noktasina aktarilir (bkz. screen_shake.gd);
	# Haptics ile ayni desen.
	ScreenShake.trauma_scale = _progress.shake_scale
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


func go_to_settings() -> void:
	await _transition(settings_scene, _configure_settings)


func go_to_level(level_id: int) -> void:
	_current_level_id = LevelLibrary.clamp_id(level_id)
	await _transition(gameplay_scene, _configure_gameplay.bind(_current_level_id),
		_current_level_id)


## [param theme_level] hangi bolumun temasi uygulanacak. 0 = notr taban tema
## (menu, ayarlar, bolum secimi): oyuncu 3. dunyadan menuye dondugunde menu
## mor kalmamali; bolum secim ekrani zaten dunya renklerini VERI olarak tasir.
##
## TEMA NEDEN BURADA UYGULANIYOR: bircok dugum rengini `@export var x :=
## Palette.Y` seklinde alir ve bu baslangic degeri sahne OLUSTURULURKEN
## okunur. Tema instantiate'ten sonra uygulanirsa o dugumler bir onceki
## dunyanin rengiyle kalir - arena duvarlarinin 70. bolumde hala 1. dunyanin
## yuzeyini gostermesinin sebebi buydu. Fade tam kapandiktan SONRA, sahne
## kurulmadan ONCE uygulamak 17 ayri script'i yamamadan hepsini duzeltir;
## ustelik degisim ekran tamamen ortuluyken olur, yani goze carpmaz.
func _transition(scene: PackedScene, configure: Callable, theme_level := 0) -> void:
	if _busy or scene == null:
		return
	_busy = true
	await _fade_to(1.0)
	Palette.apply_theme(PaletteThemes.for_level(theme_level))
	_apply_background_theme()
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
		# Editorun kendi GERI dugmesi ayni koseyi kullaniyor; orada kose
		# dugmesi gizlenir (uc parmak jesti calismaya devam eder).
		_debug_panel.set_toggle_visible(not (instance is LevelEditor))


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
		menu.settings_requested.connect(go_to_settings)
		return

	var settings := screen as SettingsScreen
	if settings != null:
		settings.menu_requested.connect(go_to_main_menu)
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
		gameplay.obstacle_kind_seen.connect(_on_obstacle_kind_seen)
		gameplay.block_mechanic_seen.connect(_on_block_mechanic_seen)
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


func _configure_settings(screen: Node) -> void:
	var settings := screen as SettingsScreen
	if settings != null:
		# Ayni ProgressStore ORNEGI verilir, kopyasi degil: ekran bir ayari
		# yazdiginda AppRoot'un elindeki nesne de guncel olmali, yoksa bir
		# sonraki save() eski degeri geri yazardi.
		settings.progress = _progress


func _configure_gameplay(screen: Node, level_id: int) -> void:
	var gameplay := screen as Gameplay
	if gameplay != null:
		# Tema burada DEGIL, _transition icinde uygulanir (sahne kurulmadan
		# once); bkz. oradaki not.
		gameplay.level_data = LevelLibrary.load_level(level_id)
		gameplay.playtest_stats = _playtest_stats
		gameplay.progress = _progress
		gameplay.aim_assist = _progress.aim_assist


## Oynanisin arkasindaki "derin uzay" katmani temanin murekkep rengini takip
## eder, boylece bant degisimi yalnizca vurgu renginde degil ZEMINDE de
## gorunur - tema degisiminin fark edilmesini saglayan asil sey budur.
##
## Sahnedeki sabit renk yerine Palette'ten okunur ve biraz koyultulur: bu
## katman arenanin ARKASINDA durur, ayni tonda olursa derinlik kaybolur.
func _apply_background_theme() -> void:
	var deep_space := get_node_or_null("BackgroundLayer/DeepSpace") as ColorRect
	if deep_space == null:
		return
	deep_space.color = Palette.INK_TOP.darkened(background_darken)
	var layer := get_node_or_null("BackgroundLayer") as CanvasLayer
	if layer != null:
		layer.visible = true


## Kazanilan yildiz yalnizca oncekinden IYIYSE kaydedilir; eski 3, yeni 1
## ise kayit 3 kalir (bkz. ProgressStore.set_level_stars_if_higher).
func _on_level_completed(level_id: int, stars: int) -> void:
	# Editorden test edilen bolum gercek ilerlemeye YAZILMAZ; henuz oyunun
	# bir parcasi degil ve kaydi kirletmesi anlamsiz olurdu.
	if _editor_level != null:
		return
	_progress.mark_completed(level_id)
	_progress.set_level_stars_if_higher(level_id, stars)


## Editordeki bolum icin de _on_level_completed ile ayni kural: gercek
## ilerlemeye yazilmaz.
func _on_obstacle_kind_seen(kind: int) -> void:
	if _editor_level != null:
		return
	_progress.mark_obstacle_kind_seen(kind)


func _on_block_mechanic_seen() -> void:
	if _editor_level != null:
		return
	_progress.mark_block_mechanic_seen()


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

## [param source_level_id] 0'dan buyukse duzenlenen sey bir RESMI bolumdur;
## editor bunu kaydederken sidecar'a yazar (bkz. LevelEditor.source_level_id).
func go_to_editor(edit_level: LevelData = null, source_level_id := 0) -> void:
	if not OS.is_debug_build():
		return
	if edit_level == null:
		_editor_batch_context.clear()
	_editor_level = edit_level
	_editor_source_level_id = source_level_id
	await _transition(level_editor_scene, _configure_editor)


func _configure_editor(screen: Node) -> void:
	var editor := screen as LevelEditor
	if editor == null:
		return
	editor.source_level_id = _editor_source_level_id
	if not _editor_batch_context.is_empty():
		editor.initial_batch_context = _editor_batch_context
	elif _editor_level != null:
		editor.level = _editor_level


## Editordeki bolumu oynatir. Kopya DEGIL ayni kaynak verilir: test sirasinda
## bolum degismez, ve geri donuldugunde duzenleme aynen durur.
func _on_editor_test_requested(edit_level: LevelData) -> void:
	var editor := _current as LevelEditor
	if editor != null:
		_editor_batch_context = editor.get_batch_context()
	_editor_level = edit_level
	# Acik kalan debug paneli arenanin ustunu ortup test edilen bolumu
	# gizlerdi. Kose dugmesi durdugu icin tek dokunusla geri acilir.
	if _debug_panel != null and is_instance_valid(_debug_panel):
		_debug_panel.hide_panel()
	await _transition(gameplay_scene, _configure_editor_gameplay,
		_editor_level.level_id if _editor_level != null else 0)


func _configure_editor_gameplay(screen: Node) -> void:
	var gameplay := screen as Gameplay
	if gameplay != null:
		# Tema burada DEGIL, _transition icinde uygulanir (sahne kurulmadan
		# once); bkz. oradaki not.
		gameplay.level_data = _editor_level
		gameplay.playtest_stats = _playtest_stats
		gameplay.progress = _progress
		# Bolum bitmez: hedefe isabet geri bildirimi oynar ama sonuc karti
		# acilmaz ve haklar tukenmez (bkz. Gameplay.practice_mode).
		gameplay.practice_mode = true


func _on_editor_closed() -> void:
	_editor_level = null
	_editor_batch_context.clear()
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
	if not (_current is Gameplay):
		return
	if _editor_level != null:
		if _step_editor_batch(-1):
			_transition(gameplay_scene, _configure_editor_gameplay,
				_editor_level.level_id if _editor_level != null else 0)
		return
	go_to_level(_current_level_id - 1)


func _on_debug_next_level() -> void:
	if not (_current is Gameplay):
		return
	if _editor_level != null:
		if _step_editor_batch(1):
			_transition(gameplay_scene, _configure_editor_gameplay,
				_editor_level.level_id if _editor_level != null else 0)
		return
	go_to_level(_current_level_id + 1)


func _step_editor_batch(direction: int) -> bool:
	var raw_levels = _editor_batch_context.get("levels", [])
	if not raw_levels is Array or raw_levels.size() <= 1:
		return false
	var index := wrapi(
		int(_editor_batch_context.get("index", 0)) + direction, 0, raw_levels.size())
	var next_level = raw_levels[index]
	if not next_level is LevelData:
		return false
	_editor_batch_context["index"] = index
	_editor_level = next_level
	return true


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
	if not OS.is_debug_build():
		return
	if _current is LevelEditor:
		return

	# OYNANAN RESMI BOLUMU DUZENLE: debug panelini bir bolumun icinde acip
	# "DUZENLE" demek, "su an oynadigim bolumu ac" anlamina gelir - eskiden
	# bos bir editor aciliyordu ve resmi bolume dokunmanin tek yolu .tres'i
	# elle bulmakti.
	#
	# KOPYA verilir: LevelLibrary'nin dondurdugu kaynak onbellege alinabildigi
	# icin dogrudan duzenlemek, o oturumda o bolumu oynayan herkesi etkilerdi.
	var gameplay := _current as Gameplay
	if gameplay != null and gameplay.level_data != null:
		var source_id := gameplay.level_data.level_id
		go_to_editor(gameplay.level_data.duplicate(true) as LevelData, source_id)
		return

	if _editor_level != null:
		go_to_editor(_editor_level, _editor_source_level_id)
		return
	# Bos bolumle acilir; editordeki "AC" ile kayitli bir bolum yuklenebilir.
	go_to_editor()
