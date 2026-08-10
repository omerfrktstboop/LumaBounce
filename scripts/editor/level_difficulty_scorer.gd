class_name LevelDifficultyScorer
extends RefCounted

## Editorde tasarlanan bir bolum icin 0-100 arasi TAHMINI zorluk skoru.
##
## Kalite puanindan farklidir: genis cozum penceresi kaliteyi artirir ama
## zorlugu azaltir. Burada asil agirlik fizik taramasinda hedefe ulasan
## atislarin oranina ve rotanin sekme sayisina verilir. Blok kapisi ile
## hareketli/oldurucu engeller kalan puani tamamlar.

const PRECISION_POINTS := 42.0
const SOLUTION_VARIETY_POINTS := 10.0
const BOUNCE_POINTS := 25.0
const COMPLEXITY_POINTS := 13.0
const BLOCK_GATE_POINTS := 10.0


static func evaluate(level: LevelData, free_scan: Dictionary,
		free_analysis: Dictionary, opened_scan: Dictionary = {},
		opened_analysis: Dictionary = {}) -> Dictionary:
	var free_hits := int(free_scan.get("hit_count", 0))
	var opened_hits := int(opened_scan.get("hit_count", 0))
	var uses_opened_route := free_hits <= 0 and opened_hits > 0
	var active_scan := opened_scan if uses_opened_route else free_scan
	var active_analysis := opened_analysis if uses_opened_route else free_analysis
	var hits := int(active_scan.get("hit_count", 0))
	var total := maxi(int(active_scan.get("total", 0)), 1)
	if hits <= 0:
		return {
			"score": 100,
			"label": "COZUMSUZ",
			"tier": 5,
			"solvable": false,
			"route_state": "none",
			"hit_count": 0,
			"solution_count": 0,
			"hit_ratio": 0.0,
			"bounces": -1,
			"robust": 0,
			"breakdown": {
				"precision": 42, "solution_variety": 10,
				"bounces": 25, "complexity": 13, "block_gate": 10,
			},
		}

	var hit_ratio := float(hits) / float(total)
	# %8 ve ustu genis/kolay, %0.1 ve alti piksel-hassas kabul edilir.
	# Logaritmik olcek, %1 ile %2 arasindaki anlamli farki kaybetmez.
	var rarity := -log(maxf(hit_ratio, 0.000001)) / log(10.0)
	var precision := roundi(clampf((rarity - 1.1) / 1.9, 0.0, 1.0) * PRECISION_POINTS)
	# Bir tek gecerli aci/guc hucresi oyuncudan kesinlik ister; 10 veya daha
	# fazla cozum ise yeterli secenek sundugu icin bu ek zorlugu tamamen siler.
	# Bu bilesen hit_ratio'dan ayri tutulur ve editor metninde acikca yazilir.
	var variety_ratio := clampf(log(float(maxi(hits, 1))) / log(10.0), 0.0, 1.0)
	var solution_variety := roundi((1.0 - variety_ratio) * SOLUTION_VARIETY_POINTS)

	var robust := int(active_analysis.get("robust", 0))
	var bounces := int(active_analysis.get("bounces", -1))
	if robust <= 0 or bounces < 0 or bounces >= 999:
		bounces = int(active_scan.get("min_bounces", 0))
	bounces = maxi(bounces, 0)
	var bounce_score := roundi(clampf(float(bounces) / 8.0, 0.0, 1.0) * BOUNCE_POINTS)

	var complexity := roundi(_complexity(level) * COMPLEXITY_POINTS)
	var block_gate := roundi(BLOCK_GATE_POINTS) if uses_opened_route else 0
	var score := clampi(
		precision + solution_variety + bounce_score + complexity + block_gate, 0, 100)
	return {
		"score": score,
		"label": label_for_score(score),
		"tier": tier_for_score(score),
		"solvable": true,
		"route_state": "opened" if uses_opened_route else "free",
		"hit_count": hits,
		"solution_count": hits,
		"hit_ratio": hit_ratio,
		"bounces": bounces,
		"robust": robust,
		"breakdown": {
			"precision": precision,
			"solution_variety": solution_variety,
			"bounces": bounce_score,
			"complexity": complexity,
			"block_gate": block_gate,
		},
	}


static func summary(result: Dictionary) -> String:
	if not bool(result.get("solvable", false)):
		return "ZORLUK 100/100 - COZUMSUZ | Hassas taramada hedefe ulasan rota yok"
	var route_text := " | bloklar kirik rota" \
		if String(result.get("route_state", "free")) == "opened" else ""
	return "ZORLUK %d/100 - %s (onerilen %d/5) | cozum %d, isabet %%%.2f, sekme %d%s" % [
		int(result.get("score", 0)), String(result.get("label", "KOLAY")),
		int(result.get("tier", 1)), int(result.get("solution_count", 0)),
		float(result.get("hit_ratio", 0.0)) * 100.0,
		int(result.get("bounces", 0)), route_text]


static func tier_for_score(score: int) -> int:
	if score < 20:
		return 1
	if score < 40:
		return 2
	if score < 60:
		return 3
	if score < 80:
		return 4
	return 5


static func label_for_score(score: int) -> String:
	match tier_for_score(score):
		1:
			return "KOLAY"
		2:
			return "ORTA"
		3:
			return "ZOR"
		4:
			return "COK ZOR"
		_:
			return "USTA"


static func _complexity(level: LevelData) -> float:
	var points := minf(float(level.panels.size()) * 0.75, 4.0)
	points += minf(float(level.breakable_blocks.size()) * 1.5, 6.0)
	for obstacle in level.obstacles:
		match obstacle.kind:
			ObstacleData.Kind.METAL_RING:
				points += 1.0
			ObstacleData.Kind.BOMB:
				points += 2.5
			ObstacleData.Kind.ROTATING_WHEEL, ObstacleData.Kind.MOVING_BAR:
				points += 3.0
			ObstacleData.Kind.PULSE_LASER:
				points += 3.5
	return clampf(points / COMPLEXITY_POINTS, 0.0, 1.0)
