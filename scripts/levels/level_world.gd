class_name LevelWorld
extends Node2D

## Bir bolumun govdelerini kuran tek yer: arena kenarlari, sekme panelleri ve
## kirilabilir bloklar.
##
## Hem headless dogrulama araci hem de oyun ici editor/uretec bunu kullanir.
## Kritik nokta: govdeler GERCEK sahnelerden (bounce_panel.tscn,
## breakable_block.tscn) uretilir, elle kurulmaz. Boylece olculen carpisma
## sekli oynanan carpisma seklinin AYNISIDIR - ayri bir "dogrulama modeli"
## olsaydi er ya da gec oyundan kayardi.
##
## Gorsel de bedava gelir: paneller ve bloklar kendi cizimlerini yaptigi icin
## bu dugum ayni zamanda editorun onizlemesidir.
##
## NOT: build() cagrildiktan sonra yeni govdelerin fizik uzayina girmesi icin
## IKI fizik karesi beklenmelidir; oncesinde yapilan sorgular onlari gormez.

const PANEL_SCENE := "res://scenes/bounce_panel.tscn"
const BLOCK_SCENE := "res://scenes/breakable_block.tscn"

var _arena: Arena
## Kirilabilir blok govdesinin RID'i -> LevelData.breakable_blocks indeksi.
var _block_rids: Dictionary = {}
var _block_count := 0


## Bolumu bastan kurar. Tekrar cagrilabilir; onceki govdeler once agactan
## CIKARILIR - yalnizca queue_free onlari kare sonuna kadar fizik dunyasinda
## birakir ve hayalet carpisma yaratirdi (bkz. Arena.rebuild).
func build(level: LevelData) -> void:
	clear()

	_arena = Arena.new()
	_arena.name = "Arena"
	add_child(_arena)
	var play_rect := _arena.get_play_rect()
	_arena.configure(level.get_left_segments(play_rect), level.get_right_segments(play_rect))

	_build_panels(level)
	_build_blocks(level)


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_arena = null
	_block_rids.clear()
	_block_count = 0


func get_space() -> PhysicsDirectSpaceState2D:
	return get_world_2d().direct_space_state


func get_play_rect() -> Rect2:
	return _arena.get_play_rect() if _arena != null else LevelData.DEFAULT_PLAY_RECT


func get_block_rids() -> Dictionary:
	return _block_rids


func get_block_count() -> int:
	return _block_count


## Editorun surukleme sirasinda dugumu dogrudan oynatabilmesi icin. Tum
## bolumu her karede yeniden kurmak yerine yalnizca ilgili govde tasinir.
func get_panel_node(index: int) -> BouncePanel:
	var found := 0
	for child in get_children():
		var panel := child as BouncePanel
		if panel == null:
			continue
		if found == index:
			return panel
		found += 1
	return null


func get_block_node(index: int) -> BreakableBlock:
	var found := 0
	for child in get_children():
		var block := child as BreakableBlock
		if block == null:
			continue
		if found == index:
			return block
		found += 1
	return null


## Bit maskesindeki kirik bloklarin RID'leri. Simulasyon bunlari sorgudan
## disladigi icin blok "kirilmis" gibi davranir ama dunya yeniden kurulmaz.
func rids_for_state(state: int) -> Array[RID]:
	var rids: Array[RID] = []
	if state == 0:
		return rids
	for rid in _block_rids:
		if state & (1 << int(_block_rids[rid])) != 0:
			rids.append(rid)
	return rids


func _build_panels(level: LevelData) -> void:
	var panel_scene := load(PANEL_SCENE) as PackedScene
	if panel_scene == null:
		push_error("LevelWorld: %s yuklenemedi." % PANEL_SCENE)
		return
	for panel_data in level.panels:
		if panel_data == null:
			continue
		var panel := panel_scene.instantiate() as BouncePanel
		panel.position = panel_data.position
		panel.rotation_degrees = panel_data.rotation_degrees
		panel.length = panel_data.length
		panel.thickness = panel_data.thickness
		add_child(panel)


func _build_blocks(level: LevelData) -> void:
	var block_scene := load(BLOCK_SCENE) as PackedScene
	if block_scene == null:
		push_error("LevelWorld: %s yuklenemedi." % BLOCK_SCENE)
		return
	for i in level.breakable_blocks.size():
		var data := level.breakable_blocks[i]
		if data == null:
			continue
		var block := block_scene.instantiate() as BreakableBlock
		block.position = data.position
		block.rotation_degrees = data.rotation_degrees
		block.block_size = data.size
		add_child(block)
		# Indeks .tres sirasidir; raporlarda "blok 2" dosyadaki 2. blok demektir.
		_block_rids[block.get_rid()] = i
		_block_count += 1
