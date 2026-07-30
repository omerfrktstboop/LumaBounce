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

@export var level_id := 1
@export var display_name := ""

@export_group("Yerlesim")
@export var launcher_position := Vector2(360.0, 1120.0)
@export var target_position := Vector2(360.0, 300.0)
@export var panels: Array[PanelData] = []

@export_group("Kenarlar")
## Her Vector2(baslangic_y, bitis_y) bir DUVAR parcasidir; aralardaki
## bosluklardan top ekran disina cikabilir. BOS birakilirsa o kenar
## bastan sona kapali kabul edilir.
@export var left_wall_segments: Array[Vector2] = []
@export var right_wall_segments: Array[Vector2] = []

@export_group("Kurallar")
@export var max_lives := 5
@export_multiline var tutorial_text := ""


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

	return problems


func _solid_wall(play_rect: Rect2) -> Array[Vector2]:
	var segments: Array[Vector2] = []
	segments.append(Vector2(
		play_rect.position.y - WALL_OVERSHOOT,
		play_rect.end.y + WALL_OVERSHOOT))
	return segments
