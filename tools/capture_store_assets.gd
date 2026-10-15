extends SceneTree

## Play Store gorselleri - GERCEK oyun render'indan.
##
## Uretilenler (her dil icin):
##   01..07_*.jpg  1080x1920 ekran goruntusu: ustte yerellestirilmis baslik,
##                 altta oyunun kendisi (HUD dahil, o dilde).
##   feature_graphic.png  1024x500 ozellik gorseli: logo + slogan + uc gercek
##                 oyun karesi.
##
## Neden gercek render: Play politikasi magaza gorsellerinin uygulamayi dogru
## temsil etmesini ister. Onceki ozellik gorseli oyunda olmayan sehir silueti,
## tugla platformlar ve yan gorunum iceriyordu.
##
## Oyun ekran disi SubViewport'larda (1080x1920, 2D'si 720x1280 referansa
## olcekli) cizilir; pencere boyutundan ve monitorden bagimsizdir. Render
## gerektigi icin --headless ile CALISMAZ.
##
## Kullanim:
##   godot --path . --script res://tools/capture_store_assets.gd
##   godot --path . --script res://tools/capture_store_assets.gd -- --lang tr,en --out builds/store_assets
##
## Gercek kayitlara dokunmaz: ilerleme verilmez (progress = null -> tanitim
## kartlari acilmaz), cuzdan gecici bir user:// dosyasidir ve sonda silinir,
## ses Master bus'ta yalnizca bu calisma icin susturulur (ayar yazilmaz).

const SHOT_SIZE := Vector2i(1080, 1920)
const REFERENCE := Vector2i(720, 1280)
const FEATURE_SIZE := Vector2i(1024, 500)
const WALLET_PATH := "user://lumabounce_store_capture_wallet.cfg"
const DEFAULT_LANGS := ["tr", "en", "es", "pt_BR", "de", "fr"]
const DEFAULT_OUT := "builds/store_assets"

## Sahne -> kullanilan bolum. Bolumler gorsel cesitlilik icin secildi: nisan
## ve sekme (1. dunya), coklu engel (3. dunya), portal (4. dunya).
const SHOTS := [
	{"id": "01_aim", "level": 21},
	{"id": "02_bounce", "level": 21},
	{"id": "03_hit", "level": 25},
	{"id": "04_obstacles", "level": 110},
	{"id": "05_portal", "level": 160},
	{"id": "06_result", "level": 21},
	{"id": "07_shop", "level": 0},
]

const CAPTIONS := {
	"tr": {
		"01_aim": ["Çek, nişan al, bırak", "200 bölüm · 4 dünya"],
		"02_bounce": ["Her sekmeyi planla", ""],
		"03_hit": ["Hedefi yak", ""],
		"04_obstacles": ["Her dünyada yeni engeller", ""],
		"05_portal": ["Portallardan ışınlan", ""],
		"06_result": ["Her bölümde 3 yıldız", ""],
		"07_shop": ["Topunu ve izini seç", ""],
		"tagline": "Sektir. Nişan al. Hedefi yak.",
	},
	"en": {
		"01_aim": ["Pull, aim, release", "200 levels · 4 worlds"],
		"02_bounce": ["Plan every bounce", ""],
		"03_hit": ["Light up the target", ""],
		"04_obstacles": ["New obstacles in every world", ""],
		"05_portal": ["Warp through portals", ""],
		"06_result": ["3 stars on every level", ""],
		"07_shop": ["Style your ball and trail", ""],
		"tagline": "Bounce. Aim. Light it up.",
	},
	"es": {
		"01_aim": ["Tira, apunta y suelta", "200 niveles · 4 mundos"],
		"02_bounce": ["Planea cada rebote", ""],
		"03_hit": ["Enciende el objetivo", ""],
		"04_obstacles": ["Nuevos obstáculos en cada mundo", ""],
		"05_portal": ["Atraviesa portales", ""],
		"06_result": ["3 estrellas en cada nivel", ""],
		"07_shop": ["Personaliza tu bola", ""],
		"tagline": "Rebota. Apunta. Enciéndelo.",
	},
	"pt_BR": {
		"01_aim": ["Puxe, mire e solte", "200 fases · 4 mundos"],
		"02_bounce": ["Planeje cada quique", ""],
		"03_hit": ["Acenda o alvo", ""],
		"04_obstacles": ["Novos obstáculos em cada mundo", ""],
		"05_portal": ["Atravesse portais", ""],
		"06_result": ["3 estrelas em cada fase", ""],
		"07_shop": ["Personalize sua bola", ""],
		"tagline": "Quique. Mire. Acenda.",
	},
	"de": {
		"01_aim": ["Ziehen, zielen, loslassen", "200 Level · 4 Welten"],
		"02_bounce": ["Plane jeden Abpraller", ""],
		"03_hit": ["Bring das Ziel zum Leuchten", ""],
		"04_obstacles": ["Neue Hindernisse in jeder Welt", ""],
		"05_portal": ["Reise durch Portale", ""],
		"06_result": ["3 Sterne in jedem Level", ""],
		"07_shop": ["Gestalte deinen Ball", ""],
		"tagline": "Abprallen. Zielen. Leuchten.",
	},
	"fr": {
		"01_aim": ["Tire, vise, relâche", "200 niveaux · 4 mondes"],
		"02_bounce": ["Prévois chaque rebond", ""],
		"03_hit": ["Illumine la cible", ""],
		"04_obstacles": ["De nouveaux obstacles à chaque monde", ""],
		"05_portal": ["Traverse les portails", ""],
		"06_result": ["3 étoiles à chaque niveau", ""],
		"07_shop": ["Personnalise ta balle", ""],
		"tagline": "Rebondis. Vise. Illumine.",
	},
}

## Kose yuvarlatma: oyun karesi cerceveye otursun diye.
const ROUND_SHADER := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(100.0);
uniform float radius = 40.0;
void fragment() {
	vec2 p = UV * rect_size;
	vec2 q = abs(p - rect_size * 0.5) - (rect_size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) - radius;
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= clamp(0.5 - d, 0.0, 1.0);
}
"""

var _out_dir := ""
var _wallet: WalletStore
var _round_shader: Shader
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("capture_store_assets: render gerekir, --headless olmadan calistirin.")
		quit(1)
		return
	var langs: Array = DEFAULT_LANGS
	var out := DEFAULT_OUT
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--lang" and i + 1 < args.size():
			langs = Array(args[i + 1].split(","))
		elif args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	_out_dir = ProjectSettings.globalize_path("res://").path_join(out)
	# Cikti proje icinde: .gdignore olmazsa editor gorselleri ice aktarir ve
	# export onlari pakete koyar (v12'nin ilk AAB'si boyle ~12 MB sismisti).
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var ignore := FileAccess.open(_out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null:
		ignore.close()
	_round_shader = Shader.new()
	_round_shader.code = ROUND_SHADER
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	_ensure_audio_manager()
	_prepare_wallet()

	for lang in langs:
		var code := String(lang)
		if not CAPTIONS.has(code):
			push_error("Desteklenmeyen dil: %s" % code)
			_failures += 1
			continue
		Locale.apply(code)
		var lang_dir := _out_dir.path_join(code)
		DirAccess.make_dir_recursive_absolute(lang_dir)
		var raw := {}
		for shot in SHOTS:
			var image := await _capture_shot(shot)
			if image == null:
				push_error("%s/%s yakalanamadi" % [code, shot["id"]])
				_failures += 1
				continue
			raw[shot["id"]] = image
			var texts: Array = CAPTIONS[code][shot["id"]]
			var framed := await _compose_screenshot(image, texts[0], texts[1], int(shot["level"]))
			var path := lang_dir.path_join("%s.jpg" % shot["id"])
			framed.save_jpg(path, 0.92)
			print("yazildi: ", path)
		if raw.has("02_bounce") and raw.has("03_hit") and raw.has("05_portal"):
			var feature := await _compose_feature(
				[raw["02_bounce"], raw["03_hit"], raw["05_portal"]], CAPTIONS[code]["tagline"])
			var feature_path := lang_dir.path_join("feature_graphic.png")
			feature.save_png(feature_path)
			print("yazildi: ", feature_path)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET_PATH))
	print("Bitti: %s (%d hata)" % [_out_dir, _failures])
	quit(1 if _failures > 0 else 0)


# --- Oyun karesi --------------------------------------------------------------

func _capture_shot(shot: Dictionary) -> Image:
	var id := String(shot["id"])
	var level_id := int(shot["level"])
	var viewport := _make_viewport(SHOT_SIZE, true)
	var image: Image = null
	if id == "07_shop":
		image = await _capture_shop(viewport)
	else:
		image = await _capture_gameplay(viewport, id, level_id)
	viewport.queue_free()
	await process_frame
	return image


func _capture_gameplay(viewport: SubViewport, id: String, level_id: int) -> Image:
	Palette.apply_theme(PaletteThemes.for_level(level_id))
	var level := load(LevelLibrary.level_path(level_id)) as LevelData
	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	gameplay.set("level_data", level)
	gameplay.set("wallet", _wallet)
	viewport.add_child(gameplay)
	await _frames(2)
	_fix_safe_areas(gameplay)
	await _frames(40)

	var ball := gameplay.get_node("Ball") as Ball
	var target := gameplay.get_node("Target") as Target
	var launcher := gameplay.get_node("Launcher") as Launcher
	var direction := Vector2.UP.rotated(deg_to_rad(level.hint_angle_degrees))
	var events := {"bounces": 0, "hit": false, "teleports": 0}
	ball.bounced.connect(func(_a, _n, _s): events["bounces"] += 1)
	ball.teleported.connect(func(_f, _t, _s): events["teleports"] += 1)
	target.hit.connect(func(_b): events["hit"] = true)

	# Atis oyuncunun yaptigi gibi yapilir: cek -> bekle -> birak. Boylece
	# kronometre (ilk gecerli nisanda baslar), top gerilimi ve guc gostergesi
	# gercek oyundaki gibi calisir; sonuc kartinda "0.0 sn" gorunmez.
	var ratio := clampf(inverse_lerp(launcher.min_power, launcher.max_power, level.hint_power), 0.0, 1.0)
	var drag := lerpf(launcher.min_drag_distance, launcher.max_drag_distance, ratio)
	var spawn := launcher.get_spawn_position()
	launcher.begin_aim(spawn)
	launcher.update_aim(spawn - direction * drag)
	if id == "01_aim":
		await _frames(20)
		return viewport.get_texture().get_image()
	await create_timer(1.1).timeout
	launcher.release_aim()
	var capture_at := {"02_bounce": 2, "04_obstacles": 2}
	for frame in 900:
		await physics_frame
		match id:
			"02_bounce", "04_obstacles":
				if events["bounces"] >= capture_at[id] or (events["hit"] and frame > 0):
					await _frames(2)
					return viewport.get_texture().get_image()
			"05_portal":
				if events["teleports"] > 0:
					await _frames(4)
					return viewport.get_texture().get_image()
			"03_hit":
				if events["hit"]:
					await _frames(9)
					return viewport.get_texture().get_image()
			"06_result":
				if events["hit"]:
					gameplay.call("notify_luma_coin_reward", 2)
					await create_timer(float(gameplay.get("result_delay")) + 1.6).timeout
					return viewport.get_texture().get_image()
	push_warning("%s: beklenen an gelmedi, son kare kullanildi" % id)
	return viewport.get_texture().get_image()


func _capture_shop(viewport: SubViewport) -> Image:
	Palette.apply_theme(PaletteThemes.for_level(0))
	var provider := MockAdProvider.new()
	var ads := AdService.new()
	ads.configure(provider, null, null)
	root.add_child(ads)
	ads.initialize()
	provider.set_rewarded_ready(MonetizationConfig.PLACEMENT_COIN_BONUS, true)
	var shop := (load("res://scenes/shop_screen.tscn") as PackedScene).instantiate()
	shop.set("wallet", _wallet)
	shop.set("ad_service", ads)
	shop.set("today_override", "2026-10-15")
	viewport.add_child(shop)
	await _frames(2)
	_fix_safe_areas(shop)
	await _frames(30)
	var image := viewport.get_texture().get_image()
	ads.queue_free()
	return image


# --- Birlestirme -------------------------------------------------------------

func _compose_screenshot(shot: Image, caption: String, sub: String, level_id: int) -> Image:
	Palette.apply_theme(PaletteThemes.for_level(level_id))
	var viewport := _make_viewport(SHOT_SIZE, false)
	var canvas := _make_canvas(viewport, Vector2(SHOT_SIZE), level_id)

	var title := _make_label(caption, 76, Palette.TEXT)
	title.position = Vector2(60.0, 110.0 if not sub.is_empty() else 150.0)
	title.size = Vector2(960.0, 180.0)
	canvas.add_child(title)
	if not sub.is_empty():
		var subtitle := _make_label(sub, 42, Palette.ACCENT)
		subtitle.position = Vector2(60.0, 280.0)
		subtitle.size = Vector2(960.0, 70.0)
		canvas.add_child(subtitle)

	var frame_width := 812.0
	var frame_rect := Rect2(Vector2((SHOT_SIZE.x - frame_width) * 0.5, 410.0),
		Vector2(frame_width, frame_width * float(SHOT_SIZE.y) / float(SHOT_SIZE.x)))
	_add_framed_shot(canvas, shot, frame_rect, 0.0, 44.0)
	await _frames(4)
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	viewport.queue_free()
	return image


func _compose_feature(shots: Array, tagline: String) -> Image:
	Palette.apply_theme(PaletteThemes.for_level(1))
	var viewport := _make_viewport(FEATURE_SIZE, false)
	var canvas := _make_canvas(viewport, Vector2(FEATURE_SIZE), 1)

	var logo := LumaLogo.new()
	logo.font_size = 70
	logo.glyph_size = 50.0
	logo.position = Vector2(48.0, 150.0)
	logo.size = Vector2(520.0, 110.0)
	canvas.add_child(logo)
	var line := _make_label(tagline, 34, Palette.TEXT_DIM)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.position = Vector2(56.0, 280.0)
	line.size = Vector2(500.0, 60.0)
	canvas.add_child(line)

	# Uc gercek oyun karesi, hafif yelpaze halinde; ortadaki ustte.
	var height := 400.0
	var width := height * float(SHOT_SIZE.x) / float(SHOT_SIZE.y)
	var centers := [Vector2(700.0, 262.0), Vector2(935.0, 262.0), Vector2(818.0, 250.0)]
	var angles := [-7.0, 7.0, 0.0]
	var order := [0, 2, 1]
	for k in 3:
		var rect := Rect2(centers[k] - Vector2(width, height) * 0.5, Vector2(width, height))
		_add_framed_shot(canvas, shots[order[k]], rect, angles[k], 22.0)
	await _frames(4)
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	viewport.queue_free()
	return image


func _make_canvas(viewport: SubViewport, canvas_size: Vector2, level_id: int) -> Control:
	var canvas := Control.new()
	canvas.size = canvas_size
	viewport.add_child(canvas)
	var background := InkBackground.new()
	canvas.add_child(background)
	var motif := WorldMotif.new()
	motif.motif = WorldMotif.motif_for_world(LevelWorlds.index_for_level(maxi(level_id, 1)))
	motif.intensity = 1.3
	canvas.add_child(motif)
	return canvas


## Oyun karesi + vurgu renginde cerceve + hafif hale. [param rect] cerceve ici.
func _add_framed_shot(canvas: Control, shot: Image, rect: Rect2, angle_deg: float,
		radius: float) -> void:
	var holder := Control.new()
	holder.position = rect.position
	holder.size = rect.size
	holder.pivot_offset = rect.size * 0.5
	holder.rotation_degrees = angle_deg
	canvas.add_child(holder)

	var glow := Panel.new()
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(Palette.INK_TOP, 1.0)
	glow_style.set_corner_radius_all(int(radius) + 6)
	glow_style.shadow_color = Color(Palette.ACCENT, 0.32)
	glow_style.shadow_size = int(radius * 0.9)
	glow_style.border_color = Color(Palette.ACCENT, 0.85)
	glow_style.set_border_width_all(5)
	glow_style.set_expand_margin_all(6.0)
	glow.add_theme_stylebox_override("panel", glow_style)
	glow.size = rect.size
	holder.add_child(glow)

	var picture := TextureRect.new()
	picture.texture = ImageTexture.create_from_image(shot)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.size = rect.size
	var material := ShaderMaterial.new()
	material.shader = _round_shader
	material.set_shader_parameter("rect_size", rect.size)
	material.set_shader_parameter("radius", radius)
	picture.material = material
	holder.add_child(picture)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


# --- Yardimcilar ----------------------------------------------------------------

func _make_viewport(size: Vector2i, game_scale: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	if game_scale:
		viewport.size_2d_override = REFERENCE
		viewport.size_2d_override_stretch = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


## SafeAreaMargin guvenli alani PENCEREDEN okur; ekran disi viewport'ta bu
## anlamsizdir (cok monitorlu masaustunde dev bir sol bosluk bile cikar).
## Telefonun centiksiz temel boslugu uygulanir.
func _fix_safe_areas(node: Node) -> void:
	if node is SafeAreaMargin:
		var margin := node as SafeAreaMargin
		margin.add_theme_constant_override("margin_left", int(margin.base_padding.x))
		margin.add_theme_constant_override("margin_right", int(margin.base_padding.x))
		margin.add_theme_constant_override("margin_top", int(margin.base_padding.y))
		margin.add_theme_constant_override("margin_bottom", int(margin.base_padding.y))
	for child in node.get_children():
		_fix_safe_areas(child)


## Magazada gorunen bakiye ve sahip olunan birkac kozmetik: bos bir magaza
## yerine oyuncunun bir sure oynadiktan sonra gordugu hal. Hicbiri SECILMEZ -
## oyun karelerinde top ve iz varsayilan gorunumde kalir (CosmeticApplier).
func _prepare_wallet() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET_PATH))
	_wallet = WalletStore.load_from_path(WALLET_PATH)
	_wallet.add(180)
	for id in ["ball_ember", "trail_comet"]:
		if CosmeticCatalog.find(id) != null:
			_wallet.purchase_cosmetic(id)


func _ensure_audio_manager() -> void:
	if root.get_node_or_null("AudioManager") != null:
		return
	var path := String(ProjectSettings.get_setting("autoload/AudioManager", "")).trim_prefix("*")
	var script := load(path) as GDScript
	if script == null:
		return
	var node := script.new() as Node
	node.name = "AudioManager"
	root.add_child(node)
	Engine.register_singleton("AudioManager", node)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
