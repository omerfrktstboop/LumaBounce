class_name MechanicIntroCard
extends Control

## "Yeni mekanik" tanitim karti: oyuncu bir mekanigi ILK kez gordugunde acilan,
## girdiyi bloklayan tam ekran kart.
##
## NEDEN KUCUK TOAST DEGIL: bir engelin KURALI ("halkanin ortasi gecirir,
## kenari sektirir", "bronz tugla iki vurus ister") tek satir metinle veya
## donen bir ikonla anlatilamaz. Burada mekanik, kucuk bir sahnede GERCEKTEN
## OYNATILARAK gosterilir - top gelir, carpar, blok catlar. Yani sabit bir
## resim degil, donguye giren canli bir gosterim.
##
## GERCEK CIZIM KODU KULLANILIR: sahnedeki halka/cark/bariyer gercek
## LevelObstacle, tuglalar gercek BreakableBlock ornekleridir. Ayri bir
## "tanitim gorseli" yoktur, bu yuzden bir engelin gorunumu degistiginde bu
## kart kendiliginden guncel kalir.
##
## FIZIK YOK: gosterimdeki topun yolu elle yazilmis, deterministik bir
## animasyondur (bkz. _advance_*). Gercek fizigi burada calistirmak, kartin
## kare hizina ve tesadufi sekmelere bagli olmasi demekti; anlatim her acilista
## birebir ayni olmali.

signal dismissed()

enum Mode { NONE, OBSTACLE, BLOCK }

## Gosterim sahnesinin ic koordinat alani (SubViewport boyutuyla ayni).
const STAGE_SIZE := Vector2(392.0, 212.0)
const DEMO_BALL_RADIUS := 11.0
const BREAKABLE_BLOCK_SCENE := preload("res://scenes/breakable_block.tscn")

# --- Tugla gosterimi zaman cizelgesi -----------------------------------------
# Anlatilan sey RENK FARKI oldugu icin iki tuglanin YAN YANA gorunur kalmasi
# sart. Bu yuzden kirilan mavi tugla dongu sonunu beklemeden hemen geri gelir;
# aksi halde donguT'nun buyuk bolumunde ekranda tek tugla kalir ve
# karsilastirma kaybolur.
const BLOCK_PERIOD := 6.0
const BLOCK_TRAVEL := 1.1
const BLOCK_RECOIL := 0.42
## (vurus_ani, tugla_index): mavi tek vurusta dagilir, bronz once catlar sonra dagilir.
const BLOCK_HITS := [
	{"at": 1.4, "brick": 0},
	{"at": 3.5, "brick": 1},
	{"at": 5.1, "brick": 1},
]
## Dagilan mavi tugla bu anda geri gelir (efekti bitsin diye kisa bir gecikme).
const BLUE_RESPAWN_AT := 2.2

@export var card_corner_radius := 30
@export var pop_time := 0.26

@onready var _card: PanelContainer = $CardCenter/Card
@onready var _kicker: Label = $CardCenter/Card/Margin/Rows/Kicker
@onready var _title: Label = $CardCenter/Card/Margin/Rows/Title
@onready var _stage_frame: PanelContainer = $CardCenter/Card/Margin/Rows/StageFrame
@onready var _stage_root: Node2D = \
	$CardCenter/Card/Margin/Rows/StageFrame/StageViewport/SubViewport/StageRoot
@onready var _description: Label = $CardCenter/Card/Margin/Rows/Description
@onready var _continue_button: LumaButton = $CardCenter/Card/Margin/Rows/ContinueButton

var _mode: Mode = Mode.NONE
var _kind: ObstacleData.Kind = ObstacleData.Kind.METAL_RING
var _time := 0.0
var _pop_tween: Tween

var _mechanic: LevelObstacle
var _ball: Node2D
var _flash: Node2D
var _bricks: Array[BreakableBlock] = []
var _brick_specs: Array[Dictionary] = []
## Tugla gosteriminde hangi dongude oldugumuz - dongu degisince sahne tazelenir.
var _block_cycle := -1
## Bir vurusun tam olarak BIR kez uygulanmasi icin: dongu her karede calisir,
## bayrak olmadan take_hit() ayni temas icin tekrar tekrar cagrilirdi.
var _consumed_passes := {}


func _ready() -> void:
	_apply_style()
	_continue_button.pressed.connect(close)
	set_process(false)
	hide()


func _apply_style() -> void:
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(Palette.SURFACE, 0.97)
	card_style.border_color = Color(Palette.SURFACE_EDGE, 1.0)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(card_corner_radius)
	card_style.corner_detail = 12
	card_style.anti_aliasing = true
	_card.add_theme_stylebox_override("panel", card_style)

	# Gosterim alani karttan bir ton KOYU: kucuk bir "ekran" hissi verir ve
	# animasyonu kartin govdesinden ayirir.
	var stage_style := StyleBoxFlat.new()
	stage_style.bg_color = Color(Palette.INK_MID, 1.0)
	stage_style.border_color = Color(Palette.SURFACE_EDGE, 0.9)
	stage_style.set_border_width_all(2)
	stage_style.set_corner_radius_all(18)
	stage_style.corner_detail = 10
	stage_style.anti_aliasing = true
	_stage_frame.add_theme_stylebox_override("panel", stage_style)

	_kicker.add_theme_color_override("font_color", Palette.ACCENT)
	_title.add_theme_color_override("font_color", Palette.TEXT)
	_description.add_theme_color_override("font_color", Palette.TEXT_DIM)


# --- Genel giris noktalari ----------------------------------------------------

## Tek bir engel turunu tanitir.
func show_obstacle(kind: ObstacleData.Kind) -> void:
	_mode = Mode.OBSTACLE
	_kind = kind
	_kicker.text = "YENİ ENGEL"
	_title.text = _obstacle_title(kind)
	_description.text = _obstacle_description(kind)
	_build_obstacle_stage(kind)
	_open()


## Kirilabilir blok mekanigini tanitir. Tek bir ObstacleData.Kind'i olmadigi
## icin ayri giris noktasi - ayrica gosterimi de farklidir: iki dayaniklilik
## seviyesini YAN YANA oynatir, cunku asil ogretilecek sey renk farkidir.
func show_block_mechanic() -> void:
	_mode = Mode.BLOCK
	_kicker.text = "YENİ MEKANİK"
	_title.text = "Kırılabilir Tuğla"
	_description.text = "Mavi tuğla tek vuruşta kırılır. Bronz tuğla iki vuruş ister: önce çatlar, sonra dağılır."
	_build_block_stage()
	_open()


func is_open() -> bool:
	return visible


## Karti kapatir ve [signal dismissed] yayar. Buton da bunu cagirir.
func close() -> void:
	if not visible:
		return
	set_process(false)
	hide()
	_clear_stage()
	_mode = Mode.NONE
	dismissed.emit()


func _open() -> void:
	show()
	_time = 0.0
	set_process(true)
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.88, 0.88)
	modulate.a = 0.0
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.set_parallel(true)
	_pop_tween.tween_property(_card, "scale", Vector2.ONE, pop_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(self, "modulate:a", 1.0, pop_time * 0.75)


# --- Metinler -----------------------------------------------------------------

func _obstacle_title(kind: ObstacleData.Kind) -> String:
	match kind:
		ObstacleData.Kind.METAL_RING:
			return "Metal Halka"
		ObstacleData.Kind.BOMB:
			return "Mayın"
		ObstacleData.Kind.ROTATING_WHEEL:
			return "Dönen Çark"
		ObstacleData.Kind.MOVING_BAR:
			return "Kayan Bariyer"
		ObstacleData.Kind.SPEED_BOOST:
			return "Hızlandırıcı"
		ObstacleData.Kind.PULSE_LASER:
			return "Lazer Bariyer"
	return "Yeni Engel"


func _obstacle_description(kind: ObstacleData.Kind) -> String:
	match kind:
		ObstacleData.Kind.METAL_RING:
			return "Halka bir at nalıdır: yalnızca üst tarafı açıktır. Alttan gelen top metal gövdeye çarpıp seker."
		ObstacleData.Kind.BOMB:
			return "Mayına dokunma. Değdiği anda atış biter ve bir top hakkın gider."
		ObstacleData.Kind.ROTATING_WHEEL:
			return "Çark sürekli döner. Kollar arasındaki boşluğu zamanlaman gerekir."
		ObstacleData.Kind.MOVING_BAR:
			return "Bariyer ileri geri kayar. Açılan boşluğu doğru anda yakala."
		ObstacleData.Kind.SPEED_BOOST:
			return "İçinden geçen top hızlanır."
		ObstacleData.Kind.PULSE_LASER:
			return "Işın aralıklarla yanar. Yanmadan hemen önce parlar; sönük olduğu anda geç."
	return ""


# --- Sahne kurulumu -----------------------------------------------------------

func _clear_stage() -> void:
	# remove_child + queue_free (yalnizca queue_free DEGIL): kart ust uste
	# acilabildigi icin eski gosterim ANINDA agactan cikmali. Sadece
	# queue_free() ertelenmis oldugundan eski dugumler bir kare daha agacta
	# kalir ve yeni "DemoBall" ile ayni isimde iki dugum olusup Godot yenisini
	# yeniden adlandirir - sonra get_node("DemoBall") yanlis dugumu bulur.
	for child in _stage_root.get_children():
		_stage_root.remove_child(child)
		child.queue_free()
	_mechanic = null
	_ball = null
	_flash = null
	_bricks.clear()
	_brick_specs.clear()
	_block_cycle = -1
	_consumed_passes.clear()


func _build_obstacle_stage(kind: ObstacleData.Kind) -> void:
	_clear_stage()
	var data := _preview_data(kind)
	_mechanic = LevelObstacle.new()
	# as_preview: gercek fizik govdesi kurulmaz - bu bir gosterim sahnesi,
	# carpismalar elle yazilmis animasyonla temsil edilir.
	_mechanic.setup(data, true)
	_stage_root.add_child(_mechanic)
	_ball = _make_demo_ball()
	_stage_root.add_child(_ball)
	_flash = _make_flash()
	_stage_root.add_child(_flash)
	_flash.hide()


## Gosterim icin olceklenmis ama ObstacleData.validate() sinirlari icinde kalan
## temsili degerler.
func _preview_data(kind: ObstacleData.Kind) -> ObstacleData:
	var data := ObstacleData.new()
	data.kind = kind
	data.position = STAGE_SIZE * 0.5
	match kind:
		ObstacleData.Kind.METAL_RING:
			data.size = Vector2(150.0, 24.0)
			data.inner_radius = 50.0
		ObstacleData.Kind.BOMB:
			data.size = Vector2(76.0, 76.0)
		ObstacleData.Kind.ROTATING_WHEEL:
			data.size = Vector2(140.0, 20.0)
			data.spoke_count = 5
			data.angular_speed_degrees = 90.0
		ObstacleData.Kind.MOVING_BAR:
			data.size = Vector2(150.0, 26.0)
			data.travel_distance = 92.0
			data.motion_period = 2.6
		ObstacleData.Kind.SPEED_BOOST:
			data.size = Vector2(64.0, 64.0)
		ObstacleData.Kind.PULSE_LASER:
			# Gosterim dongusu gercek bolumlerden KISA tutulur: kart birkac
			# saniye acik kalir, oyuncu bir tam yanip-sonme dongusunu ve
			# uyari parlamasini o surede gorebilmeli.
			data.size = Vector2(300.0, 14.0)
			data.motion_period = 2.6
			data.pulse_on_ratio = 0.55
	return data


func _build_block_stage() -> void:
	_clear_stage()
	# Iki dayaniklilik seviyesi yan yana: soldaki tek vurusluk (mavi), sagdaki
	# iki vurusluk (bronz). Renk farki ancak yan yana gorununce ogretilir.
	_brick_specs = [
		{"position": Vector2(STAGE_SIZE.x * 0.28, 92.0), "hit_points": 1},
		{"position": Vector2(STAGE_SIZE.x * 0.72, 92.0), "hit_points": 2},
	]
	_spawn_bricks()
	_ball = _make_demo_ball()
	_stage_root.add_child(_ball)


func _spawn_bricks() -> void:
	for brick in _bricks:
		if is_instance_valid(brick):
			# Bkz. _clear_stage(): aninda agactan cikarilmali, yoksa dongu
			# basinda eski ve yeni tuglalar bir kare ust uste binerdi.
			_stage_root.remove_child(brick)
			brick.queue_free()
	_bricks.clear()
	for spec in _brick_specs:
		var brick: BreakableBlock = BREAKABLE_BLOCK_SCENE.instantiate()
		brick.block_size = Vector2(104.0, 34.0)
		brick.hit_points = int(spec["hit_points"])
		# Gosterim sahnesi fizige katilmaz.
		brick.collision_layer = 0
		brick.collision_mask = 0
		brick.position = spec["position"]
		_stage_root.add_child(brick)
		_bricks.append(brick)


func _make_demo_ball() -> Node2D:
	var ball := Node2D.new()
	ball.name = "DemoBall"
	ball.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(DEMO_BALL_RADIUS + 4.0, 20), Color(Palette.ACCENT, 0.22)))
	ball.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(DEMO_BALL_RADIUS, 20), Palette.ACCENT))
	ball.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(DEMO_BALL_RADIUS * 0.42, 14,
			Vector2(-DEMO_BALL_RADIUS * 0.26, -DEMO_BALL_RADIUS * 0.28)),
		Palette.ACCENT_CORE))
	return ball


## Mayin temasinda kullanilan kisa parlama.
func _make_flash() -> Node2D:
	var flash := Node2D.new()
	flash.name = "Flash"
	flash.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(46.0, 24), Color(Palette.HAZARD, 0.35)))
	flash.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(24.0, 20), Color(Palette.HAZARD_CORE, 0.9)))
	return flash


# --- Gosterim animasyonu ------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	match _mode:
		Mode.OBSTACLE:
			_advance_obstacle_demo()
		Mode.BLOCK:
			_advance_block_demo()


func _advance_obstacle_demo() -> void:
	if _mechanic != null and is_instance_valid(_mechanic):
		# Cark/bariyer kendi gercek hareket matematigiyle oynatilir.
		_mechanic.apply_motion_time(_time)
	if _ball == null or not is_instance_valid(_ball):
		return
	match _kind:
		ObstacleData.Kind.METAL_RING:
			_demo_ring()
		ObstacleData.Kind.BOMB:
			_demo_bomb()
		ObstacleData.Kind.ROTATING_WHEEL:
			_demo_wheel()
		ObstacleData.Kind.MOVING_BAR:
			_demo_moving_bar()
		ObstacleData.Kind.SPEED_BOOST:
			_demo_speed_boost()
		ObstacleData.Kind.PULSE_LASER:
			_demo_laser()


## Halka: iki asamali dongu. Once ORTADAN gecer (acik), sonra KENARA carpip
## seker (kati). Halkanin kuralinin tamami bu iki atista.
## Halka bir AT NALIDIR: 24 segmentin 20'si doludur, yalnizca ustteki ~60
## derecelik yay aciktir (bkz. ObstacleGeometry.ring_rects - olculdu).
##
## Gosterim eskiden "top tam ortadan yukari gecer" diye animasyon oynatiyordu;
## bu FIZIKSEL OLARAK IMKANSIZDI, cunku alttan gelen top govdenin dolu
## kismina carpar. Yanlis ogretilen bir kural, hic ogretmemekten daha
## kotudur: oyuncu izinin gectigi yere nisan alip sekince hatayi kendinde
## arar. Simdi iki atis gercek davranisi gosterir.
func _demo_ring() -> void:
	var centre := STAGE_SIZE * 0.5
	# Govdenin orta yaricapi (ic 50 ile dis 75 arasi) - temas noktasi burasi.
	var body_radius := 62.0
	var period := 4.6
	var t := fmod(_time, period)

	if t < period * 0.55:
		# 1. atis: alttan gelir, METAL GOVDEYE carpar ve yana seker.
		var p := t / (period * 0.55)
		var impact_y := centre.y + body_radius
		if p < 0.5:
			_ball.position = Vector2(
				centre.x, lerpf(STAGE_SIZE.y + 20.0, impact_y, p / 0.5))
		else:
			# Sekme YANA dogru, kadraj icinde kalacak kadar: kareden cikan bir
			# top gosterimde "bir an hicbir sey yok" olarak okunuyordu.
			var away := (p - 0.5) / 0.5
			_ball.position = Vector2(
				lerpf(centre.x, centre.x - 136.0, away),
				lerpf(impact_y, impact_y + 30.0, away))
		_ball.modulate.a = 1.0
		return

	# 2. atis: USTTEKI bosluktan iceri iner - halkanin tek girisi orasi.
	var p2 := (t - period * 0.55) / (period * 0.45)
	_ball.position = Vector2(
		centre.x, lerpf(-20.0, centre.y, minf(p2 / 0.72, 1.0)))
	_ball.modulate.a = 1.0


## Mayin: dokunur, parlar, atis biter. Top kaybolur ve dongu bastan baslar.
func _demo_bomb() -> void:
	var centre := STAGE_SIZE * 0.5
	var period := 3.0
	var t := fmod(_time, period)
	var impact_y := centre.y + 46.0
	if t < 1.5:
		var p := t / 1.5
		_ball.position = Vector2(centre.x, lerpf(STAGE_SIZE.y + 20.0, impact_y, p))
		_ball.modulate.a = 1.0
		_flash.hide()
		return
	# Temas: top kaybolur, kisa bir parlama kalir.
	_ball.modulate.a = 0.0
	if t < 2.1:
		_flash.position = Vector2(centre.x, impact_y)
		_flash.show()
		var fade := 1.0 - (t - 1.5) / 0.6
		_flash.modulate.a = fade
		_flash.scale = Vector2.ONE * lerpf(0.5, 1.25, 1.0 - fade)
	else:
		_flash.hide()


## Lazer: iki atis, iki sonuc. Ogretilen sey ZAMANLAMA oldugu icin gosterim
## isinin kendi dongusuyle SENKRON olmali - dongu suresi lazerin periyodunun
## tam kati (2 x 2.6) secildi, boylece birinci atis her zaman isin sonukken,
## ikincisi her zaman isin yanikken gerceklesir. Kayarlarsa kart bazen
## "iki top da gecti" gosterirdi ve kural anlasilmazdi.
##
## Isinin kendisi ayrica animasyonlu: _mechanic.apply_motion_time(_time)
## gercek LevelObstacle mantigini calistirir, yani karttaki yanip sonme
## oyundakiyle ayni koddan gelir.
func _demo_laser() -> void:
	var centre := STAGE_SIZE * 0.5
	var period := 5.2
	var t := fmod(_time, period)

	if t < 2.6:
		# 1. atis: isin SONUKKEN gecer. Cizgiyi t~1.6'da kesecek sekilde
		# baslatilir; lazer 1.43'te sondugu icin gecis guvenli.
		var p := clampf((t - 0.75) / 1.7, 0.0, 1.0)
		_ball.position = Vector2(
			centre.x - 58.0, lerpf(STAGE_SIZE.y + 20.0, -20.0, p))
		_ball.modulate.a = 1.0 if t > 0.6 else 0.0
		_flash.hide()
		return

	# 2. atis: isin YANIYORKEN carpar - atis biter.
	var t2 := t - 2.6
	var hit_at := 1.15
	var hit_x := centre.x + 58.0
	if t2 < hit_at:
		_ball.position = Vector2(
			hit_x, lerpf(STAGE_SIZE.y + 20.0, centre.y, t2 / hit_at))
		_ball.modulate.a = 1.0
		_flash.hide()
		return

	_ball.modulate.a = 0.0
	if t2 < hit_at + 0.6:
		_flash.position = Vector2(hit_x, centre.y)
		_flash.show()
		var fade := 1.0 - (t2 - hit_at) / 0.6
		_flash.modulate.a = fade
		_flash.scale = Vector2.ONE * lerpf(0.5, 1.25, 1.0 - fade)
	else:
		_flash.hide()


## Cark: kollar arasindaki bosluktan gecmeye calisir; kola carpinca seker.
func _demo_wheel() -> void:
	var centre := STAGE_SIZE * 0.5
	var period := 3.2
	var t := fmod(_time, period)
	var impact_y := centre.y + 52.0
	if t < 1.3:
		var p := t / 1.3
		_ball.position = Vector2(centre.x - 6.0, lerpf(STAGE_SIZE.y + 20.0, impact_y, p))
	elif t < 2.4:
		var away := (t - 1.3) / 1.1
		_ball.position = Vector2(
			lerpf(centre.x - 6.0, centre.x - 130.0, away),
			lerpf(impact_y, impact_y + 70.0, away))
	else:
		_ball.position = Vector2(centre.x - 6.0, STAGE_SIZE.y + 20.0)
	_ball.modulate.a = 1.0


## Kayan bariyer: bariyer bir yana kaydiginda acilan bosluktan gecer.
## Topun zamanlamasi bariyerin GERCEK hareket fonksiyonundan turetilir, boylece
## gosterim her zaman tutarli olur.
func _demo_moving_bar() -> void:
	var centre := STAGE_SIZE * 0.5
	var period := 2.6
	var t := fmod(_time, period)
	var p := t / period
	# Bariyer sinus ile saga-sola kayar; bariyer nereye kaydiysa top KARSI
	# taraftaki bosluktan gecer. Zamanlama bariyerin GERCEK hareket
	# fonksiyonundan turetilir, boylece gosterim her acilista tutarli olur.
	var bar_offset: float = _mechanic.data.motion_position(_time).x - _mechanic.data.position.x
	var lane_x := centre.x + 96.0
	if bar_offset > 0.0:
		lane_x = centre.x - 96.0
	_ball.position = Vector2(lane_x, lerpf(STAGE_SIZE.y + 20.0, -20.0, p))
	_ball.modulate.a = 1.0


func _demo_speed_boost() -> void:
	var centre := STAGE_SIZE * 0.5
	var period := 2.4
	var p := fmod(_time, period) / period
	# Hizlandiriciyi gectikten sonra belirgin sekilde hizlanir (ustel egri).
	var eased := p * p if p < 0.5 else 0.25 + (p - 0.5) * 1.5
	_ball.position = Vector2(centre.x, lerpf(STAGE_SIZE.y + 20.0, -20.0, clampf(eased, 0.0, 1.0)))
	_ball.modulate.a = 1.0


## Tugla: soldaki mavi tuglayi tek vurusta, sagdaki bronz tuglayi iki vurusta
## kirar; sonra sahne tazelenir. Vuruslar gercek BreakableBlock.take_hit()
## uzerinden yapilir, yani catlak/dagilma efektleri oyundakiyle birebir aynidir.
func _advance_block_demo() -> void:
	if _ball == null or not is_instance_valid(_ball):
		return
	var cycle := int(_time / BLOCK_PERIOD)
	var t := fmod(_time, BLOCK_PERIOD)
	# Yeni dongu: tum tuglalari geri getir ve vurus bayraklarini sifirla.
	if cycle != _block_cycle:
		_block_cycle = cycle
		_consumed_passes.clear()
		_spawn_bricks()
	# Mavi tugla dongu ortasinda geri gelir, boylece bronzla yan yana kalir.
	if t >= BLUE_RESPAWN_AT and not _consumed_passes.has("blue_back") \
			and _is_brick_gone(0):
		_consumed_passes["blue_back"] = true
		_respawn_brick(0)

	for hit_index in BLOCK_HITS.size():
		var entry: Dictionary = BLOCK_HITS[hit_index]
		var hit_at := float(entry["at"])
		var start_time := hit_at - BLOCK_TRAVEL
		if t < start_time or t > hit_at + BLOCK_RECOIL:
			continue
		var brick_index := int(entry["brick"])
		if _is_brick_gone(brick_index):
			continue
		var brick := _bricks[brick_index]
		var to := brick.position + Vector2(0.0, brick.block_size.y * 0.5 + DEMO_BALL_RADIUS)
		var from := Vector2(brick.position.x, STAGE_SIZE.y + 24.0)
		if t <= hit_at:
			_ball.position = from.lerp(to, (t - start_time) / BLOCK_TRAVEL)
			_ball.modulate.a = 1.0
		else:
			# Temas sonrasi: asagi geri seker ve solar.
			var away := (t - hit_at) / BLOCK_RECOIL
			_ball.position = to.lerp(from, away * 0.55)
			_ball.modulate.a = 1.0 - away * 0.75
			_apply_pending_hit(hit_index, brick)
		return
	# Atislar arasi: top sahnede durmasin.
	_ball.modulate.a = 0.0


func _is_brick_gone(index: int) -> bool:
	if index >= _bricks.size():
		return true
	var brick := _bricks[index]
	return not is_instance_valid(brick) or brick.is_broken()


## Tek bir tuglayi yerine geri koyar (tum sahneyi kurmadan).
func _respawn_brick(index: int) -> void:
	if index >= _brick_specs.size():
		return
	var old := _bricks[index]
	if is_instance_valid(old):
		_stage_root.remove_child(old)
		old.queue_free()
	var spec: Dictionary = _brick_specs[index]
	var brick: BreakableBlock = BREAKABLE_BLOCK_SCENE.instantiate()
	brick.block_size = Vector2(104.0, 34.0)
	brick.hit_points = int(spec["hit_points"])
	brick.collision_layer = 0
	brick.collision_mask = 0
	brick.position = spec["position"]
	_stage_root.add_child(brick)
	_bricks[index] = brick


func _apply_pending_hit(pass_index: int, brick: BreakableBlock) -> void:
	if _consumed_passes.has(pass_index):
		return
	_consumed_passes[pass_index] = true
	if is_instance_valid(brick) and not brick.is_broken():
		brick.take_hit()
