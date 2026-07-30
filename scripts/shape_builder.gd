class_name ShapeBuilder
extends RefCounted

## Kucuk geometri yardimcilari.
## Harici gorsel asset kullanmadigimiz icin tum sekiller Polygon2D / Line2D
## nokta listeleri olarak kod ile uretilir.


## Merkezi [param center] olan bir daire.
static func circle(radius: float, segments: int = 32, center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Yatay kapsul (stadyum): uclari tam yuvarlak dikdortgen.
## CapsuleShape2D ile birebir ayni sekli verir.
static func stadium(length: float, thickness: float, cap_segments: int = 10) -> PackedVector2Array:
	var radius := thickness * 0.5
	var half := maxf(length * 0.5 - radius, 0.0)
	var points := PackedVector2Array()
	for i in cap_segments + 1:
		var angle := lerpf(-PI * 0.5, PI * 0.5, float(i) / float(cap_segments))
		points.append(Vector2(half + cos(angle) * radius, sin(angle) * radius))
	for i in cap_segments + 1:
		var angle := lerpf(PI * 0.5, PI * 1.5, float(i) / float(cap_segments))
		points.append(Vector2(-half + cos(angle) * radius, sin(angle) * radius))
	return points


## Koseleri yumusatilmis dikdortgen.
static func rounded_rect(size: Vector2, corner_radius: float, corner_segments: int = 6) -> PackedVector2Array:
	var radius := minf(corner_radius, minf(size.x, size.y) * 0.5)
	var half := size * 0.5
	var centers := [
		Vector2(half.x - radius, half.y - radius),
		Vector2(-half.x + radius, half.y - radius),
		Vector2(-half.x + radius, -half.y + radius),
		Vector2(half.x - radius, -half.y + radius),
	]
	var start_angles := [0.0, PI * 0.5, PI, PI * 1.5]
	var points := PackedVector2Array()
	for corner in 4:
		var center: Vector2 = centers[corner]
		var start: float = start_angles[corner]
		for i in corner_segments + 1:
			var angle := start + PI * 0.5 * float(i) / float(corner_segments)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Line2D ile kapali kontur cizebilmek icin ilk noktayi sona ekler.
static func closed_loop(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return points
	var loop := points.duplicate()
	loop.append(points[0])
	return loop


## Hazir noktalardan yumusatilmis bir Polygon2D uretir.
static func make_polygon(points: PackedVector2Array, color: Color) -> Polygon2D:
	var polygon := Polygon2D.new()
	polygon.polygon = points
	polygon.color = color
	polygon.antialiased = true
	return polygon


## Ince, temiz bir kontur cizgisi uretir.
static func make_outline(points: PackedVector2Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = closed_loop(points)
	line.default_color = color
	line.width = width
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	return line
