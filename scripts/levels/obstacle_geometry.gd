class_name ObstacleGeometry
extends RefCounted

## Runtime collision sekilleri ile LevelSolver'in analitik sekilleri icin
## ortak geometri tanimlari.

const RING_SEGMENTS := 24
const EPSILON := 0.00001


static func ring_rects(data: ObstacleData) -> Array[Dictionary]:
	var rects: Array[Dictionary] = []
	var outer := data.outer_radius()
	var inner := clampf(data.inner_radius, 1.0, outer - 1.0)
	var middle := (outer + inner) * 0.5
	var thickness := outer - inner
	var chord := 2.0 * middle * sin(PI / float(RING_SEGMENTS)) + thickness * 0.42
	# Leave an opening at the top by skipping segments.
	# For 24 segments, let's skip 4 segments (60 degrees).
	var skip_count := 4
	var start_idx := skip_count / 2
	var end_idx := RING_SEGMENTS - (skip_count - start_idx)
	for i in range(start_idx, end_idx):
		var angle := TAU * float(i) / float(RING_SEGMENTS) - PI * 0.5 # Start from top
		rects.append({
			"center": Vector2.RIGHT.rotated(angle) * middle,
			"size": Vector2(chord, thickness),
			"rotation": angle + PI * 0.5,
		})
	return rects


static func wheel_local_shapes(data: ObstacleData) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	var outer := data.outer_radius()
	var thickness := clampf(data.size.y, 14.0, outer * 0.65)
	var hub_radius := maxf(thickness * 0.82, outer * 0.19)
	var spoke_length := maxf(outer - hub_radius * 0.45, thickness)
	for i in clampi(data.spoke_count, 3, 8):
		var angle := TAU * float(i) / float(data.spoke_count)
		shapes.append({
			"shape": "rect",
			"center": Vector2.RIGHT.rotated(angle) * spoke_length * 0.5,
			"size": Vector2(spoke_length, thickness),
			"rotation": angle,
		})
	shapes.append({"shape": "circle", "center": Vector2.ZERO, "radius": hub_radius})
	return shapes


static func dynamic_shapes(obstacles: Array[ObstacleData], seconds: float) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	for data in obstacles:
		if data == null:
			continue
		match data.kind:
			ObstacleData.Kind.ROTATING_WHEEL:
				var rotation := data.motion_rotation(seconds)
				for local in wheel_local_shapes(data):
					var shape: Dictionary = local.duplicate()
					var local_center: Vector2 = local["center"]
					shape["center"] = data.position + local_center.rotated(rotation)
					if String(local["shape"]) == "rect":
						shape["rotation"] = float(local["rotation"]) + rotation
					shapes.append(shape)
			ObstacleData.Kind.MOVING_BAR:
				shapes.append({
					"shape": "rect",
					"center": data.motion_position(seconds),
					"size": data.size,
					"rotation": data.motion_rotation(seconds),
				})
	return shapes


static func hazard_shapes(obstacles: Array[ObstacleData]) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	for i in obstacles.size():
		var data = obstacles[i]
		if data != null and data.kind == ObstacleData.Kind.BOMB:
			shapes.append({
				"shape": "circle",
				"center": data.position,
				"radius": data.bomb_radius(),
				"hazard_reason": "bomb",
				"obstacle_index": i,
			})
		elif data != null and data.kind == ObstacleData.Kind.SPEED_BOOST:
			shapes.append({
				"shape": "circle",
				"center": data.position,
				"radius": data.outer_radius(),
				"hazard_reason": "speed_boost",
				"obstacle_index": i,
			})
	return shapes


static func all_shapes(obstacles: Array[ObstacleData], seconds: float) -> Array[Dictionary]:
	var shapes := dynamic_shapes(obstacles, seconds)
	for data in obstacles:
		if data == null:
			continue
		if data.kind == ObstacleData.Kind.METAL_RING:
			var base_rotation := deg_to_rad(data.rotation_degrees)
			for local in ring_rects(data):
				shapes.append({
					"shape": "rect",
					"center": data.position + (local["center"] as Vector2).rotated(base_rotation),
					"size": local["size"],
					"rotation": float(local["rotation"]) + base_rotation,
				})
	shapes.append_array(hazard_shapes(obstacles))
	return shapes


static func cast_circle(from: Vector2, motion: Vector2, radius: float,
		shapes: Array[Dictionary], ignored_hazards: Array = []) -> Dictionary:
	if motion.is_zero_approx():
		return {}
	var best := {}
	var best_fraction := 2.0
	for shape in shapes:
		var hit := {}
		if String(shape.get("shape", "")) == "circle":
			hit = _cast_circle_circle(
				from, motion, radius, shape["center"], float(shape["radius"]))
		else:
			hit = _cast_circle_rect(
				from, motion, radius, shape["center"], shape["size"],
				float(shape.get("rotation", 0.0)))
		if hit.is_empty() or float(hit["fraction"]) >= best_fraction:
			continue
		if shape.has("hazard_reason") and shape.has("obstacle_index"):
			if int(shape["obstacle_index"]) in ignored_hazards:
				continue
		best_fraction = float(hit["fraction"])
		best = hit
		if shape.has("hazard_reason"):
			best["hazard_reason"] = String(shape["hazard_reason"])
			best["obstacle_index"] = int(shape.get("obstacle_index", -1))
	return best


static func overlaps_circle(center: Vector2, radius: float,
		shapes: Array[Dictionary]) -> bool:
	for shape in shapes:
		if String(shape.get("shape", "")) == "circle":
			if center.distance_to(shape["center"]) <= radius + float(shape["radius"]):
				return true
			continue
		var local := (center - (shape["center"] as Vector2)).rotated(
			-float(shape.get("rotation", 0.0)))
		var half: Vector2 = (shape["size"] as Vector2) * 0.5
		var closest := Vector2(
			clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
		if local.distance_to(closest) <= radius:
			return true
	return false


static func _cast_circle_circle(from: Vector2, motion: Vector2, radius: float,
		center: Vector2, other_radius: float) -> Dictionary:
	var expanded := radius + other_radius
	var relative := from - center
	var c := relative.length_squared() - expanded * expanded
	if c <= 0.0:
		var overlap_normal := relative.normalized()
		if overlap_normal.is_zero_approx():
			overlap_normal = -motion.normalized()
		return {"fraction": 0.0, "normal": overlap_normal}
	var a := motion.length_squared()
	if a <= EPSILON:
		return {}
	var b := 2.0 * relative.dot(motion)
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return {}
	var fraction := (-b - sqrt(discriminant)) / (2.0 * a)
	if fraction < 0.0 or fraction > 1.0:
		return {}
	var normal := (from + motion * fraction - center).normalized()
	if motion.dot(normal) >= 0.0:
		return {}
	return {"fraction": fraction, "normal": normal}


static func _cast_circle_rect(from: Vector2, motion: Vector2, radius: float,
		center: Vector2, size: Vector2, rotation: float) -> Dictionary:
	var point := (from - center).rotated(-rotation)
	var velocity := motion.rotated(-rotation)
	var half := size * 0.5
	var closest := Vector2(
		clampf(point.x, -half.x, half.x), clampf(point.y, -half.y, half.y))
	var delta := point - closest
	if delta.length_squared() <= radius * radius:
		var overlap_normal := delta.normalized()
		if overlap_normal.is_zero_approx():
			var x_depth := half.x + radius - absf(point.x)
			var y_depth := half.y + radius - absf(point.y)
			if x_depth < y_depth:
				overlap_normal = Vector2(_axis_sign(point.x, -velocity.x), 0.0)
			else:
				overlap_normal = Vector2(0.0, _axis_sign(point.y, -velocity.y))
		return {"fraction": 0.0, "normal": overlap_normal.rotated(rotation)}

	var best_fraction := 2.0
	var best_normal := Vector2.ZERO
	for raw_side in [-1.0, 1.0]:
		var side: float = raw_side
		if absf(velocity.x) > EPSILON:
			var tx: float = (side * (half.x + radius) - point.x) / velocity.x
			var y: float = point.y + velocity.y * tx
			var nx := Vector2(side, 0.0)
			if tx >= 0.0 and tx <= 1.0 and absf(y) <= half.y and velocity.dot(nx) < 0.0:
				if tx < best_fraction:
					best_fraction = tx
					best_normal = nx
		if absf(velocity.y) > EPSILON:
			var ty: float = (side * (half.y + radius) - point.y) / velocity.y
			var x: float = point.x + velocity.x * ty
			var ny := Vector2(0.0, side)
			if ty >= 0.0 and ty <= 1.0 and absf(x) <= half.x and velocity.dot(ny) < 0.0:
				if ty < best_fraction:
					best_fraction = ty
					best_normal = ny

	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(sx * half.x, sy * half.y)
			var corner_hit := _cast_point_circle(point, velocity, corner, radius)
			if corner_hit.is_empty():
				continue
			var fraction: float = corner_hit["fraction"]
			var contact := point + velocity * fraction
			if sx * contact.x < half.x - EPSILON or sy * contact.y < half.y - EPSILON:
				continue
			if fraction < best_fraction:
				best_fraction = fraction
				best_normal = corner_hit["normal"]

	if best_fraction > 1.0:
		return {}
	return {"fraction": best_fraction, "normal": best_normal.rotated(rotation).normalized()}


static func _cast_point_circle(point: Vector2, motion: Vector2,
		center: Vector2, radius: float) -> Dictionary:
	var relative := point - center
	var a := motion.length_squared()
	if a <= EPSILON:
		return {}
	var b := 2.0 * relative.dot(motion)
	var c := relative.length_squared() - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return {}
	var fraction := (-b - sqrt(discriminant)) / (2.0 * a)
	if fraction < 0.0 or fraction > 1.0:
		return {}
	var normal := (point + motion * fraction - center).normalized()
	if motion.dot(normal) >= 0.0:
		return {}
	return {"fraction": fraction, "normal": normal}


static func _axis_sign(value: float, fallback: float) -> float:
	if not is_zero_approx(value):
		return signf(value)
	if not is_zero_approx(fallback):
		return signf(fallback)
	return 1.0
