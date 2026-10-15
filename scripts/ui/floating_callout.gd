class_name FloatingCallout
extends Node2D

## Dunyada kisa sure beliren ovgu yazisi ("5 SEKME!"). Kendi kendini siler.
##
## Metni CAGIRAN cevirir (tr("%d SEKME!") % n gibi bicimli metinler otomatik
## ceviriyle bulunamaz); bu yuzden etiketin otomatik cevirisi kapalidir.
## Yalnizca gorsel: oyun durumuna dokunmaz, fizige baglanmaz.

const RISE := 64.0
const LIFETIME := 1.0
const FADE_TIME := 0.3


static func spawn(parent: Node, at: Vector2, text: String, color: Color,
		font_size := 46) -> FloatingCallout:
	var node := FloatingCallout.new()
	node.name = "FloatingCallout"
	node.position = at
	node.z_index = 40

	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(Palette.INK_TOP, 0.95))
	label.add_theme_constant_override("outline_size", 10)
	node.add_child(label)

	parent.add_child(node)
	node._play(label)
	return node


func _play(label: Label) -> void:
	label.reset_size()
	label.position = -label.size * 0.5
	scale = Vector2.ONE * 0.55
	modulate.a = 0.0

	# Hizli bir "pop" ve hemen okunur hale gelme: sonuc karti isabetten kisa
	# sure sonra acildigi icin yazi ilk ~0.15 sn icinde tam gorunur olmali.
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector2.ONE * 1.12, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(self, "scale", Vector2.ONE, 0.14) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var drift := create_tween().set_parallel(true)
	drift.tween_property(self, "position:y", position.y - RISE, LIFETIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	drift.tween_property(self, "modulate:a", 1.0, 0.1)
	drift.tween_property(self, "modulate:a", 0.0, FADE_TIME) \
		.set_delay(LIFETIME - FADE_TIME)
	drift.chain().tween_callback(queue_free)
