extends SceneTree

## Belirli bir resmi bolum araligini gercek AppRoot/Gameplay akisi uzerinden
## PNG olarak yakalar. Renderer gerektirdigi icin --headless ile calistirma.
##
## Kullanim:
##   godot --path . --script res://tools/capture_level_band.gd -- --from 25 --to 50

var _from_level := 25
var _to_level := 50
var _output_dir := ProjectSettings.globalize_path("res://screnshot")


func _initialize() -> void:
	_parse_args()
	_run.call_deferred()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--from" and i + 1 < args.size():
			_from_level = int(args[i + 1])
		elif args[i] == "--to" and i + 1 < args.size():
			_to_level = int(args[i + 1])
		elif args[i] == "--output" and i + 1 < args.size():
			_output_dir = args[i + 1]


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_output_dir)
	var packed := load("res://scenes/app_root.tscn") as PackedScene
	var app := packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	for level_id in range(_from_level, _to_level + 1):
		if not LevelLibrary.is_valid_id(level_id):
			push_warning("Bolum %d kutuphanede yok; atlandi." % level_id)
			continue
		app.call("go_to_level", level_id)
		# AppRoot gecisi 0.28 sn; oyun sahnesinin iki kare de cizilmesini bekle.
		await create_timer(0.70).timeout
		await process_frame
		await process_frame
		var image := root.get_texture().get_image()
		var path := _output_dir.path_join("level_%d.png" % level_id)
		var error := image.save_png(path)
		if error == OK:
			print("YAKALANDI %d -> %s" % [level_id, path])
		else:
			push_error("Bolum %d ekran goruntusu kaydedilemedi: %d" % [level_id, error])

	root.remove_child(app)
	app.queue_free()
	print("YAKALAMA TAMAMLANDI %d-%d" % [_from_level, _to_level])
	quit()
