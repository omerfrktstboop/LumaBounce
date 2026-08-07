class_name LevelData
extends Resource

## Tek bir bolumun tum yerlesimi.
##
## Bolumler res://levels/level_XX.tres dosyalarinda saklanir; gameplay.gd
## sahnede sabit panel bulundurmaz, her seyi buradan kurar.

## Referans oyun alani (arena.gd play_size ile ayni). Dogrulama icin kullanilir.
const DEFAULT_PLAY_RECT := Rect2(0.0, 0.0, 720.0, 1280.0)
## Duvar segmenti belirtilmeyen kenarlar bu araliktaki tek parca duvarla kapanir.
const WALL_OVERSHOOT := 320.0

@export_group("Kimlik")
## DEGISMEZ benzersiz kimlik ("level_001"). Kayit dosyasi bolumleri BUNUNLA
## anar; sira degisse veya araya yeni bolum eklense bile oyuncunun ilerlemesi
## dogru bolumde kalir. Bos birakilirsa level_id'den turetilir (bkz. uid()),
## boylece mevcut 125 .tres dosyasi degistirilmeden calismaya devam eder.
@export var level_uid := ""
## Bolumun kacinci sirada OYNANDIGI. Kimlikten AYRIDIR: sirayi degistirmek
## icin bu alani degistirmek yeterlidir, kayitlar etkilenmez. 0 birakilirsa
## level_id kullanilir.
@export var display_order := 0
## Hangi dunya/tema paketine ait. Tema paleti ve ileride dunya bazli klasorleme
## icin (bkz. PaletteThemes.for_level).
@export var theme_id := ""
## Kaba zorluk etiketi (1-5). Yalnizca siralama/raporlama icindir; oynanisi
## etkilemez - gercek zorluk olcusu LevelSolver'in saglam hucre sayisidir.
@export_range(0, 5, 1) var difficulty := 0
## Saniye cinsinden sure siniri; 0 = sinirsiz (bugunku davranis).
@export var time_limit := 0.0

@export var level_id := 1
@export var display_name := ""

@export_group("Yerlesim")
@export var launcher_position := Vector2(360.0, 1120.0)
@export var target_position := Vector2(360.0, 300.0)
@export var target_scale := 1.0
@export var ball_scale := 1.0
@export var panels: Array[PanelData] = []
## Topun kirabilecegi bloklar. Bos birakilirsa bolumde hic blok yoktur ve
## davranis eskisiyle birebir aynidir (bkz. BreakableField).
@export var breakable_blocks: Array[BreakableBlockData] = []
## Metal halka, bomba, donen cark ve kayan bariyerler. Eski bolumlerde bos
## kalir; panel/blok fizigini veya 720x1280 koordinatlarini degistirmez.
@export var obstacles: Array[ObstacleData] = []

@export_group("Kenarlar")
## Her Vector2(baslangic_y, bitis_y) bir DUVAR parcasidir; aralardaki
## bosluklardan top ekran disina cikabilir. BOS birakilirsa o kenar
## bastan sona kapali kabul edilir.
@export var left_wall_segments: Array[Vector2] = []
@export var right_wall_segments: Array[Vector2] = []

@export_group("Kurallar")
@export var max_lives := 5
@export_multiline var tutorial_text := ""

@export_group("Yildiz Hedefleri")
## 2 yildiz icin: sure VE atis sayisi birlikte saglanmali.
@export var two_star_max_seconds := 45.0
@export var two_star_max_shots := 4
## 3 yildiz icin daha siki esikler; ikisi de saglanmali.
@export var three_star_max_seconds := 25.0
@export var three_star_max_shots := 2


## Bu bolumun KALICI kimligi. Kayit dosyasinda ve migration'da kullanilan
## tek dogru anahtar budur.
##
## Alan bos birakildiginda level_id'den turetilir ("level_007"): boylece
## mevcut bolum dosyalarinin hicbirine dokunmadan uid tabanli kayda gecilebilir
## ve ileride bir bolume acikca uid verildiginde o kazanir. Turetim SABIT bir
## kural oldugu icin ayni dosya her zaman ayni uid'i uretir.
func uid() -> String:
	var explicit := level_uid.strip_edges()
	return explicit if not explicit.is_empty() else uid_for(level_id)


## Bir bolum numarasindan kanonik uid. Kayit gocu (migration) eski tamsayi
## anahtarlari bununla cevirir - bkz. ProgressStore._migrate_from_v0().
static func uid_for(number: int) -> String:
	return "level_%03d" % number


## Bolumun oynanma sirasi. display_order verilmemisse level_id'ye duser.
func order() -> int:
	return display_order if display_order > 0 else level_id


func get_left_segments(play_rect := DEFAULT_PLAY_RECT) -> Array[Vector2]:
	return left_wall_segments if not left_wall_segments.is_empty() else _solid_wall(play_rect)


func get_right_segments(play_rect := DEFAULT_PLAY_RECT) -> Array[Vector2]:
	return right_wall_segments if not right_wall_segments.is_empty() else _solid_wall(play_rect)


## Sorun bulunmazsa bos dizi doner. Bos degilse bolum yuklenmemelidir.
func validate(play_rect := DEFAULT_PLAY_RECT) -> PackedStringArray:
	var problems := PackedStringArray()

	if level_id < 1:
		problems.append("level_id 1'den kucuk olamaz (%d)" % level_id)
	if max_lives < 1:
		problems.append("max_lives en az 1 olmali (%d)" % max_lives)
	if not play_rect.has_point(launcher_position):
		problems.append("launcher_position oyun alani disinda %s" % launcher_position)
	if not play_rect.has_point(target_position):
		problems.append("target_position oyun alani disinda %s" % target_position)

	for i in panels.size():
		var panel := panels[i]
		if panel == null:
			problems.append("panel %d bos" % i)
			continue
		problems.append_array(panel.validate(i))

	for i in breakable_blocks.size():
		var block := breakable_blocks[i]
		if block == null:
			problems.append("blok %d bos" % i)
			continue
		problems.append_array(block.validate(i))

	for i in obstacles.size():
		var obstacle := obstacles[i]
		if obstacle == null:
			problems.append("engel %d bos" % i)
			continue
		problems.append_array(obstacle.validate(i, play_rect))

	problems.append_array(_validate_star_targets())
	return problems


## Bolum tamamlandiginda kazanilan yildiz. Sure VE atis kosulu BIRLIKTE
## saglanmali: 18 sn + 3 atis, sure 3 yildizlik olsa bile 2 yildiz verir.
## Basarisiz bolumde hic cagrilmaz (yildiz yalnizca tamamlamayla kazanilir).
func calculate_stars(seconds: float, shots: int) -> int:
	if seconds <= three_star_max_seconds and shots <= three_star_max_shots:
		return 3
	if seconds <= two_star_max_seconds and shots <= two_star_max_shots:
		return 2
	return 1


func _validate_star_targets() -> PackedStringArray:
	var problems := PackedStringArray()

	if two_star_max_seconds <= 0.0:
		problems.append("two_star_max_seconds pozitif olmali (%s)" % two_star_max_seconds)
	if three_star_max_seconds <= 0.0:
		problems.append("three_star_max_seconds pozitif olmali (%s)" % three_star_max_seconds)
	if two_star_max_shots <= 0:
		problems.append("two_star_max_shots pozitif olmali (%d)" % two_star_max_shots)
	if three_star_max_shots <= 0:
		problems.append("three_star_max_shots pozitif olmali (%d)" % three_star_max_shots)

	# 3 yildiz her zaman 2 yildizdan daha siki olmali, yoksa 3 yildiz
	# kosulu 2 yildizdan once saglanip esikler anlamsizlasir.
	if three_star_max_seconds > two_star_max_seconds:
		problems.append("three_star_max_seconds (%s) two_star_max_seconds'tan (%s) buyuk olamaz" % [
			three_star_max_seconds, two_star_max_seconds])
	if three_star_max_shots > two_star_max_shots:
		problems.append("three_star_max_shots (%d) two_star_max_shots'tan (%d) buyuk olamaz" % [
			three_star_max_shots, two_star_max_shots])

	return problems


func _solid_wall(play_rect: Rect2) -> Array[Vector2]:
	var segments: Array[Vector2] = []
	segments.append(Vector2(
		play_rect.position.y - WALL_OVERSHOOT,
		play_rect.end.y + WALL_OVERSHOOT))
	return segments
