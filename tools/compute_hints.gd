extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir.
##
## Her bolum icin bir IPUCU ATISI hesaplar (aci + guc) ve bolum dosyasina
## yazar.
##
## NEDEN CEVRIMDISI: ipucu, solver'in izgara taramasindan gelir - binlerce
## simulasyon. Bunu oyuncu "ipucu" tusuna bastiginda yapmak telefonu
## saniyelerce dondururdu. Burada bir kez hesaplanip .tres'e yazilir; oyun
## calisma aninda yalnizca TEK bir atis simule edip yolunu cizer.
##
## HANGI ATIS SECILIR: LevelSolver.analyse_robust'in "best" hucresi, yani
## saglam (dort komsusu da isabet eden) hucreler arasinda EN AZ SEKMEYLE
## gidenin acisi/gucu. En kisa rota degil, en TOLERANSLI rota - ipucunun isi
## oyuncuyu piksel hassasiyetinde bir atisa mahkum etmek degil, tikandigi
## yerde calisan bir yon gostermek.
##
## Bloklu bolumlerde tarama bloklar KIRILMIS halde yapilir: kirilmamis halde
## zaten rota yoktur (bandin sozlesmesi bu), dolayisiyla ipucu "once bloklari
## kir, sonra su acidan at" demis olur.
##
## Kullanim:
##   godot --headless --path . --script res://tools/compute_hints.gd
##   godot --headless --path . --script res://tools/compute_hints.gd -- --only 42,126
##   godot --headless --path . --script res://tools/compute_hints.gd -- --from 1 --to 50

const ANGLE_STEP := 2.0
const POWER_STEP := 50.0

var _from := 1
var _to := 0
var _only: Array[int] = []
var _solver: LevelSolver
var _world: LevelWorld


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--from" and i + 1 < args.size():
			_from = int(args[i + 1])
		elif args[i] == "--to" and i + 1 < args.size():
			_to = int(args[i + 1])
		elif args[i] == "--only" and i + 1 < args.size():
			for piece in args[i + 1].split(",", false):
				var clean := piece.strip_edges()
				if clean.is_valid_int():
					_only.append(int(clean))
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	_solver = LevelSolver.from_scenes()

	var wanted: Array[int] = _only.duplicate()
	if wanted.is_empty():
		var last := _to if _to > 0 else LevelLibrary.last_level_id()
		for level_id in range(_from, last + 1):
			wanted.append(level_id)

	var written := 0
	var skipped: Array[int] = []
	for level_id in wanted:
		if await _compute(level_id):
			written += 1
		else:
			skipped.append(level_id)

	print("")
	print("OZET yazilan=%d ipucusuz=%d" % [written, skipped.size()])
	if not skipped.is_empty():
		print("ipucu bulunamayan bolumler: %s" % str(skipped))
	# Ipucu bulunamamasi bir HATA DEGILDIR (bkz. LevelData.has_hint): o
	# bolumde ipucu tusu pasif gorunur. Bu yuzden cikis kodu her zaman 0.
	quit(0)


func _compute(level_id: int) -> bool:
	var path := LevelLibrary.level_path(level_id)
	var level := load(path) as LevelData
	if level == null:
		push_warning("compute_hints: %s yuklenemedi." % path)
		return false

	_world = LevelWorld.new()
	root.add_child(_world)
	_world.build(level)
	_solver.bind_space(_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
	await physics_frame
	await physics_frame

	var spawn := _solver.spawn_position(level.launcher_position)
	var play_rect := _world.get_play_rect()
	# Bloklu bolumde tarama BLOKLAR KIRILMIS halde: kirilmamis halde rota
	# olmamasi bandin kurali, dolayisiyla ipucu kirildiktan SONRAKI atisi
	# gosterir.
	var excluded: Array[RID] = []
	if not level.breakable_blocks.is_empty():
		excluded = _world.rids_for_state(_world.get_all_broken_state())
	var scan := _solver.scan(
		spawn, level.target_position, play_rect, excluded, ANGLE_STEP, POWER_STEP)
	var analysis := LevelSolver.analyse_robust(scan)

	root.remove_child(_world)
	_world.queue_free()
	_world = null
	await process_frame

	if int(analysis["robust"]) <= 0:
		print("LEVEL %3d ipucu yok (saglam hucre bulunamadi)" % level_id)
		return false

	var angle := float(analysis["best_angle"])
	var power := float(analysis["best_power"])
	if is_equal_approx(level.hint_angle_degrees, angle) \
			and is_equal_approx(level.hint_power, power):
		print("LEVEL %3d ipucu zaten guncel (aci %.1f, guc %.0f)" % [level_id, angle, power])
		return true

	level.hint_angle_degrees = angle
	level.hint_power = power
	var error := ResourceSaver.save(level, path)
	if error != OK:
		push_error("compute_hints: %s yazilamadi (%d)" % [path, error])
		return false
	print("LEVEL %3d ipucu: aci %.1f deg, guc %.0f  (saglam %d, sekme %d)" % [
		level_id, angle, power, int(analysis["robust"]), int(analysis["bounces"])])
	return true
