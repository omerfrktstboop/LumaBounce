class_name LevelQualityScorer
extends RefCounted

## Solver gecerliligi zorunlu; kalan puan tolerans, yenilik, okunabilirlik ve
## secilen sablona anlamli rota/blok katkisi uzerinden hesaplanir.


func score(level: LevelData, solver: Dictionary, novelty: Dictionary,
		template_id: String) -> Dictionary:
	var physics := 30.0 if bool(solver.get("ok", false)) else 0.0
	var robust := int(solver.get("robust", 0))
	var tolerance := clampf(float(robust) / 30.0, 0.0, 1.0) * 25.0
	var novelty_points := clampf(float(novelty.get("novelty_score", 0)) / 100.0, 0.0, 1.0) * 20.0
	if bool(novelty.get("strong_penalty", false)):
		novelty_points *= 0.35
	var readability := _readability(level) * 15.0
	var route := _route_contribution(level, solver, template_id) * 10.0
	var total := physics + tolerance + novelty_points + readability + route
	if physics < 30.0 or bool(novelty.get("reject", false)):
		total = 0.0
	return {
		"quality_score": clampi(roundi(total), 0, 100),
		"breakdown": {
			"physics": roundi(physics),
			"tolerance": roundi(tolerance),
			"novelty": roundi(novelty_points),
			"readability": roundi(readability),
			"route": roundi(route),
		},
	}


func _readability(level: LevelData) -> float:
	var checks := 0.0
	var passed := 0.0
	checks += 1.0
	if _nearest_object_distance(level.launcher_position, level) >= 100.0:
		passed += 1.0
	checks += 1.0
	if _nearest_object_distance(level.target_position, level) >= 90.0:
		passed += 1.0
	checks += 1.0
	if level.panels.size() + level.breakable_blocks.size() + level.obstacles.size() <= 8:
		passed += 1.0
	checks += 1.0
	var long_panels := 0
	for panel in level.panels:
		if panel.length > 400.0:
			long_panels += 1
	if long_panels <= 1:
		passed += 1.0
	checks += 1.0
	if not _objects_overlap_heavily(level):
		passed += 1.0
	return passed / checks


func _route_contribution(level: LevelData, solver: Dictionary, template_id: String) -> float:
	var robust := int(solver.get("robust", 0))
	var opened := int(solver.get("opened_robust", robust))
	match template_id:
		"two_routes":
			return 1.0 if int(solver.get("route_clusters", 1)) >= 2 else 0.35
		"safe_block_route", "multi_shot":
			return 1.0 if not level.breakable_blocks.is_empty() and opened > robust else 0.0
		"ricochet_chain":
			return 1.0 if int(solver.get("bounces", 0)) >= 5 else 0.0
		"block_corridor":
			return 1.0 if (int(solver.get("solution_shots", 0)) >= 2
				and int(solver.get("broken_state", 0)) != 0) else 0.0
		"kinetic_course":
			var has_dynamic := false
			for obstacle in level.obstacles:
				if obstacle.kind in [
						ObstacleData.Kind.ROTATING_WHEEL, ObstacleData.Kind.MOVING_BAR]:
					has_dynamic = true
					break
			return 1.0 if has_dynamic else 0.0
		"block_free_mastery":
			return 1.0 if bool(solver.get("block_free", false)) else 0.0
		_:
			# Alternatif rota istemeyen sablon cezalandirilmaz.
			return 1.0


func _nearest_object_distance(point: Vector2, level: LevelData) -> float:
	var nearest := INF
	for panel in level.panels:
		nearest = minf(nearest, point.distance_to(panel.position) - panel.length * 0.5)
	for block in level.breakable_blocks:
		nearest = minf(nearest, point.distance_to(block.position) - block.size.length() * 0.5)
	for obstacle in level.obstacles:
		nearest = minf(nearest, point.distance_to(obstacle.position) - obstacle.size.length() * 0.5)
	return nearest


func _objects_overlap_heavily(level: LevelData) -> bool:
	var centers: Array[Vector2] = []
	for panel in level.panels:
		centers.append(panel.position)
	for block in level.breakable_blocks:
		centers.append(block.position)
	for obstacle in level.obstacles:
		centers.append(obstacle.position)
	for i in centers.size():
		for j in range(i + 1, centers.size()):
			if centers[i].distance_to(centers[j]) < 56.0:
				return true
	return false
