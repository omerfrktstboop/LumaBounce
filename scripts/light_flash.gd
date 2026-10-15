class_name LightFlash
extends Node2D

## Temas anindaki yumusak isik patlamasi. Kendi kendini siler.
##
## SparkBurst "hangi yone" savruldugunu cizer; bu ise "isik" hissini verir:
## eklemeli (additive) karisimla cizilen, buyuyup sonen bir hale. Shader yok -
## ust uste binen birkac yari saydam daire merkezde parlak, kenarda soluk bir
## gecis verir ve GL Compatibility'de mobilde ihmal edilebilir maliyetlidir.
##
## Rastgelelik yok, fizige dokunmaz: yalnizca gorsel.

const LIFETIME := 0.24
const LAYERS := 5

## Tum flaslar ayni malzemeyi paylasir; her temas icin yeni kaynak uretilmez.
static var _additive: CanvasItemMaterial

var _radius := 40.0
var _color := Palette.ACCENT
var _strength := 1.0
var _lifetime := LIFETIME
var _progress := 0.0:
	set(value):
		_progress = value
		queue_redraw()


static func flash(parent: Node, at: Vector2, radius: float, color: Color,
		strength := 1.0, lifetime := LIFETIME) -> LightFlash:
	var node := LightFlash.new()
	node.name = "LightFlash"
	node.position = at
	node._radius = maxf(radius, 1.0)
	node._color = color
	node._strength = clampf(strength, 0.0, 1.0)
	node._lifetime = maxf(lifetime, 0.01)
	node.material = _additive_material()
	parent.add_child(node)
	node._play()
	return node


static func _additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


func _play() -> void:
	var tween := create_tween()
	tween.tween_property(self, "_progress", 1.0, _lifetime) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(queue_free)


func _draw() -> void:
	var fade := 1.0 - _progress
	var alpha := fade * fade * _strength
	if alpha <= 0.01:
		return
	# Hale hizla acilir ve sonerken biraz daha buyur: "patlama" okunur.
	var reach := _radius * (0.55 + 0.45 * _progress)
	for i in LAYERS:
		var t := float(i) / float(LAYERS)
		draw_circle(Vector2.ZERO, reach * (1.0 - t * 0.82), Color(_color, alpha * 0.16))
