extends CanvasLayer

signal closed

@onready var video_player: VideoStreamPlayer = $Panel/VideoPlayer
@onready var label: Label = $Panel/Label

func play_tutorial(kind_id: String, display_name: String) -> void:
	label.text = "Yeni Engel: " + display_name
	
	# Try to load a video file named after the kind_id (e.g., "bomb.ogv")
	var video_path = "res://assets/tutorials/" + kind_id + ".ogv"
	if ResourceLoader.exists(video_path):
		var stream = load(video_path)
		if stream is VideoStream:
			video_player.stream = stream
			video_player.play()
	else:
		print("Tutorial video not found: ", video_path)
	
	show()
	get_tree().paused = true

func _on_close_button_pressed() -> void:
	video_player.stop()
	hide()
	get_tree().paused = false
	closed.emit()
