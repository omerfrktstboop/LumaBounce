extends Node

var current = 1
var _taking = false

func _ready():
	DirAccess.make_dir_absolute("D:/Windows/Desktop/LumaBounce/screnshot")
	set_process(true)
	print("Screenshotting started!")

func _process(_delta):
	if _taking:
		return

	if current > LevelLibrary.last_level_id():
		print("Screenshotting done!")
		queue_free()
		return

	# Check if level exists
	var path := "res://levels/level_%02d.tres" % current
	if not ResourceLoader.exists(path):
		path = "res://levels/level_%03d.tres" % current
	if not ResourceLoader.exists(path):
		current += 1
		return

	_taking = true
	var app = get_node_or_null("/root/AppRoot")
	if app:
		app.go_to_level(current)
		# Wait for fade (0.28s) + a little bit of render time
		await get_tree().create_timer(0.6).timeout

		# Ensure we are in Gameplay screen
		if app._current is Gameplay:
			var img = get_viewport().get_texture().get_image()
			img.save_png("D:/Windows/Desktop/LumaBounce/screnshot/level_" + str(current) + ".png")
			print("Saved screenshot for level ", current)

	current += 1
	_taking = false
