class_name LevelNoveltyScorer
extends RefCounted

## Geometriyi arena boyutuna gore normalize ederek resmi, kayitli ve ayni
## batch'teki bolumlerle karsilastirir. Yatay ayna ayrica olculur.

const REJECT_SIMILARITY := 90.0
const PENALTY_SIMILARITY := 75.0


func default_references(include_previous_generated := false) -> Array[Dictionary]:
	var references: Array[Dictionary] = []
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		references.append({
			"name": "Resmi %02d" % level_id,
			"level": LevelLibrary.load_level(level_id),
			"metrics": {},
		})
	for level_name in CustomLevelStore.list_names(CustomLevelStore.Bucket.SAVED):
		var level := CustomLevelStore.load_level(CustomLevelStore.Bucket.SAVED, level_name)
		if level != null:
			references.append({"name": "Kayit/%s" % level_name, "level": level, "metrics": {}})
	if include_previous_generated:
		for level_name in CustomLevelStore.list_names(CustomLevelStore.Bucket.GENERATED):
			var level := CustomLevelStore.load_level(CustomLevelStore.Bucket.GENERATED, level_name)
			if level != null:
				references.append({
					"name": "Onceki uretim/%s" % level_name,
					"level": level,
					"metrics": {},
				})
	return references


func score(level: LevelData, metrics: Dictionary, references: Array) -> Dictionary:
	var best_similarity := 0.0
	var best_name := ""
	var best_reasons := PackedStringArray()
	var mirrored := false
	for i in references.size():
		var reference := _normalize_reference(references[i], i)
		if reference.is_empty():
			continue
		var direct := _similarity(level, metrics, reference["level"], reference["metrics"], false)
		var mirror := _similarity(level, metrics, reference["level"], reference["metrics"], true)
		var use_mirror := float(mirror["score"]) > float(direct["score"])
		var result: Dictionary = mirror if use_mirror else direct
		if float(result["score"]) > best_similarity:
			best_similarity = float(result["score"])
			best_name = String(reference["name"])
			best_reasons = result["reasons"]
			mirrored = use_mirror
	var novelty := clampf(100.0 - best_similarity, 0.0, 100.0)
	return {
		"novelty_score": roundi(novelty),
		"similarity": roundi(best_similarity),
		"most_similar_level": best_name,
		"similarity_reasons": best_reasons,
		"mirrored_match": mirrored,
		"reject": best_similarity >= REJECT_SIMILARITY,
		"strong_penalty": best_similarity >= PENALTY_SIMILARITY,
	}


func _similarity(candidate: LevelData, candidate_metrics: Dictionary,
		reference: LevelData, reference_metrics: Dictionary, mirror_reference: bool) -> Dictionary:
	var weighted := 0.0
	var total_weight := 0.0
	var reasons := PackedStringArray()
	var count_score := _count_similarity(candidate.panels.size(), reference.panels.size())
	weighted += count_score * 8.0
	total_weight += 8.0
	if count_score >= 0.9:
		reasons.append("panel sayisi")
	var block_count_score := _count_similarity(
		candidate.breakable_blocks.size(), reference.breakable_blocks.size())
	weighted += block_count_score * 6.0
	total_weight += 6.0
	if block_count_score >= 0.9:
		reasons.append("blok sayisi")
	var compare_obstacles := (
		not candidate.obstacles.is_empty() or not reference.obstacles.is_empty())
	if compare_obstacles:
		var obstacle_count_score := _count_similarity(
			candidate.obstacles.size(), reference.obstacles.size())
		weighted += obstacle_count_score * 6.0
		total_weight += 6.0
		if obstacle_count_score >= 0.9:
			reasons.append("engel sayisi")

	var launcher_ref := _mirror_point(reference.launcher_position) if mirror_reference else reference.launcher_position
	var target_ref := _mirror_point(reference.target_position) if mirror_reference else reference.target_position
	var launcher_score := _point_similarity(candidate.launcher_position, launcher_ref)
	var target_score := _point_similarity(candidate.target_position, target_ref)
	weighted += launcher_score * 5.0 + target_score * 10.0
	total_weight += 15.0
	if launcher_score >= 0.9:
		reasons.append("launcher konumu")
	if target_score >= 0.9:
		reasons.append("hedef konumu")

	var panel_score := _panel_similarity(candidate.panels, reference.panels, mirror_reference)
	var block_score := _block_similarity(
		candidate.breakable_blocks, reference.breakable_blocks, mirror_reference)
	var wall_score := _wall_similarity(candidate, reference, mirror_reference)
	weighted += panel_score * 35.0 + block_score * 15.0 + wall_score * 8.0
	total_weight += 58.0
	if panel_score >= 0.86:
		reasons.append("panel geometrisi")
	if block_score >= 0.86:
		reasons.append("blok geometrisi")
	if wall_score >= 0.9:
		reasons.append("duvar bosluklari")
	if compare_obstacles:
		var obstacle_score := _obstacle_similarity(
			candidate.obstacles, reference.obstacles, mirror_reference)
		weighted += obstacle_score * 20.0
		total_weight += 20.0
		if obstacle_score >= 0.86:
			reasons.append("engel geometrisi")

	var metric_pairs := [
		["bounces", 4.0, 5.0, "sekme sayisi"],
		["robust", 4.0, 40.0, "saglam hucre"],
	]
	for pair in metric_pairs:
		if candidate_metrics.has(pair[0]) and reference_metrics.has(pair[0]):
			var metric_score := _scalar_similarity(
				float(candidate_metrics[pair[0]]), float(reference_metrics[pair[0]]), float(pair[2]))
			weighted += metric_score * float(pair[1])
			total_weight += float(pair[1])
			if metric_score >= 0.9:
				reasons.append(String(pair[3]))
	if candidate_metrics.has("block_free") and reference_metrics.has("block_free"):
		var free_score := 1.0 if bool(candidate_metrics["block_free"]) == bool(reference_metrics["block_free"]) else 0.0
		weighted += free_score * 2.0
		total_weight += 2.0
	if candidate_metrics.has("opened_robust") and reference_metrics.has("opened_robust"):
		var candidate_growth := float(candidate_metrics["opened_robust"]) - float(candidate_metrics.get("robust", 0))
		var reference_growth := float(reference_metrics["opened_robust"]) - float(reference_metrics.get("robust", 0))
		weighted += _scalar_similarity(candidate_growth, reference_growth, 40.0) * 3.0
		total_weight += 3.0

	return {
		"score": 100.0 * weighted / maxf(total_weight, 0.001),
		"reasons": reasons,
	}


func _panel_similarity(a: Array[PanelData], b: Array[PanelData], mirrored: bool) -> float:
	if a.is_empty() and b.is_empty():
		return 1.0
	if a.is_empty() or b.is_empty():
		return 0.0
	var aa := _panel_features(a, false)
	var bb := _panel_features(b, mirrored)
	var paired := mini(aa.size(), bb.size())
	var total := 0.0
	for i in paired:
		var point_score := _point_similarity(aa[i]["position"], bb[i]["position"])
		var angle_score := _scalar_similarity(aa[i]["angle"], bb[i]["angle"], 90.0)
		var length_score := _scalar_similarity(aa[i]["length"], bb[i]["length"], 420.0)
		total += point_score * 0.55 + angle_score * 0.25 + length_score * 0.20
	return (total / float(maxi(aa.size(), bb.size()))) if paired > 0 else 0.0


func _block_similarity(a: Array[BreakableBlockData], b: Array[BreakableBlockData], mirrored: bool) -> float:
	if a.is_empty() and b.is_empty():
		return 1.0
	if a.is_empty() or b.is_empty():
		return 0.0
	var aa := _block_features(a, false)
	var bb := _block_features(b, mirrored)
	var paired := mini(aa.size(), bb.size())
	var total := 0.0
	for i in paired:
		var point_score := _point_similarity(aa[i]["position"], bb[i]["position"])
		var width_score := _scalar_similarity(aa[i]["width"], bb[i]["width"], 360.0)
		total += point_score * 0.75 + width_score * 0.25
	return (total / float(maxi(aa.size(), bb.size()))) if paired > 0 else 0.0


func _panel_features(panels: Array[PanelData], mirrored: bool) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for panel in panels:
		values.append({
			"position": _mirror_point(panel.position) if mirrored else panel.position,
			"angle": -panel.rotation_degrees if mirrored else panel.rotation_degrees,
			"length": panel.length,
		})
	values.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a["position"].y, b["position"].y):
			return a["position"].y < b["position"].y
		if not is_equal_approx(a["position"].x, b["position"].x):
			return a["position"].x < b["position"].x
		return a["angle"] < b["angle"])
	return values


func _block_features(blocks: Array[BreakableBlockData], mirrored: bool) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for block in blocks:
		values.append({
			"position": _mirror_point(block.position) if mirrored else block.position,
			"width": block.size.x,
		})
	values.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a["position"].y, b["position"].y):
			return a["position"].y < b["position"].y
		return a["position"].x < b["position"].x)
	return values


func _obstacle_similarity(a: Array[ObstacleData], b: Array[ObstacleData],
		mirrored: bool) -> float:
	if a.is_empty() and b.is_empty():
		return 1.0
	if a.is_empty() or b.is_empty():
		return 0.0
	var aa := _obstacle_features(a, false)
	var bb := _obstacle_features(b, mirrored)
	var paired := mini(aa.size(), bb.size())
	var total := 0.0
	for i in paired:
		var kind_score := 1.0 if aa[i]["kind"] == bb[i]["kind"] else 0.0
		var point_score := _point_similarity(aa[i]["position"], bb[i]["position"])
		var size_score := _scalar_similarity(aa[i]["size"], bb[i]["size"], 300.0)
		var motion_score := _scalar_similarity(aa[i]["motion"], bb[i]["motion"], 260.0)
		total += kind_score * 0.35 + point_score * 0.40 + size_score * 0.15 + motion_score * 0.10
	return total / float(maxi(aa.size(), bb.size()))


func _obstacle_features(obstacles: Array[ObstacleData], mirrored: bool) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for obstacle in obstacles:
		values.append({
			"kind": obstacle.kind,
			"position": _mirror_point(obstacle.position) if mirrored else obstacle.position,
			"size": obstacle.size.x,
			"motion": obstacle.travel_distance if obstacle.kind == ObstacleData.Kind.MOVING_BAR \
				else (absf(obstacle.angular_speed_degrees) \
					if obstacle.kind == ObstacleData.Kind.ROTATING_WHEEL else 0.0),
		})
	values.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["kind"]) != int(b["kind"]):
			return int(a["kind"]) < int(b["kind"])
		if not is_equal_approx(a["position"].y, b["position"].y):
			return a["position"].y < b["position"].y
		return a["position"].x < b["position"].x)
	return values


func _wall_similarity(a: LevelData, b: LevelData, mirrored: bool) -> float:
	var b_left := b.right_wall_segments if mirrored else b.left_wall_segments
	var b_right := b.left_wall_segments if mirrored else b.right_wall_segments
	return (_segments_similarity(a.left_wall_segments, b_left)
		+ _segments_similarity(a.right_wall_segments, b_right)) * 0.5


func _segments_similarity(a: Array[Vector2], b: Array[Vector2]) -> float:
	if a.is_empty() and b.is_empty():
		return 1.0
	if a.size() != 2 or b.size() != 2:
		return 0.0
	return (_scalar_similarity(a[0].y, b[0].y, 1280.0)
		+ _scalar_similarity(a[1].x, b[1].x, 1280.0)) * 0.5


func _normalize_reference(value: Variant, index: int) -> Dictionary:
	if value is LevelData:
		return {"name": "Referans %d" % (index + 1), "level": value, "metrics": {}}
	if value is Dictionary and value.get("level", null) is LevelData:
		return {
			"name": String(value.get("name", "Referans %d" % (index + 1))),
			"level": value["level"],
			"metrics": value.get("metrics", {}),
		}
	return {}


func _mirror_point(point: Vector2) -> Vector2:
	return Vector2(720.0 - point.x, point.y)


func _point_similarity(a: Vector2, b: Vector2) -> float:
	var normalized := Vector2((a.x - b.x) / 720.0, (a.y - b.y) / 1280.0)
	# 30-40 px'lik varyasyonlar hala yakin sayilir; yuzlerce piksellik
	# tasarim farki ise yapisal eslesmelerin arkasinda kaybolmaz.
	return clampf(1.0 - normalized.length() * 3.0, 0.0, 1.0)


func _scalar_similarity(a: float, b: float, scale: float) -> float:
	return clampf(1.0 - absf(a - b) / maxf(scale, 0.001), 0.0, 1.0)


func _count_similarity(a: int, b: int) -> float:
	return 1.0 - float(abs(a - b)) / float(maxi(maxi(a, b), 1))
