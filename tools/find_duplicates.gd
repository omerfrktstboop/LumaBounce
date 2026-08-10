extends SceneTree

func _init() -> void:
	print("Checking levels for similarities...")
	var levels: Array = []

	for i in range(1, 156):
		var path := "res://levels/level_%02d.tres" % i
		if not ResourceLoader.exists(path):
			path = "res://levels/level_%03d.tres" % i
		if not ResourceLoader.exists(path):
			continue

		var res = load(path)
		if res:
			levels.append({"id": i, "data": res})

	print("Loaded ", levels.size(), " levels.")
	var duplicates = []
	var handled = {}

	for i in range(levels.size()):
		if handled.has(i): continue

		var sim = []
		var l1 = levels[i]["data"]
		for j in range(i + 1, levels.size()):
			if handled.has(j): continue
			var l2 = levels[j]["data"]

			var score = 0.0
			var total = 0.0

			if l1.launcher_position.distance_to(l2.launcher_position) < 10.0: score += 1
			total += 1
			if l1.target_position.distance_to(l2.target_position) < 10.0: score += 1
			total += 1

			# Compare obstacles
			total += 2
			if l1.obstacles.size() == l2.obstacles.size():
				score += 1
				var obs_match = true
				for o_idx in range(l1.obstacles.size()):
					var o1 = l1.obstacles[o_idx]
					var o2 = l2.obstacles[o_idx]
					if o1.kind != o2.kind or o1.position.distance_to(o2.position) > 10.0:
						obs_match = false
						break
				if obs_match:
					score += 1

			# Compare breakable_blocks
			total += 2
			if l1.breakable_blocks.size() == l2.breakable_blocks.size():
				score += 1
				var block_match = true
				for b_idx in range(l1.breakable_blocks.size()):
					var b1 = l1.breakable_blocks[b_idx]
					var b2 = l2.breakable_blocks[b_idx]
					if b1.position.distance_to(b2.position) > 10.0:
						block_match = false
						break
				if block_match:
					score += 1

			# Compare panels
			total += 2
			if l1.panels.size() == l2.panels.size():
				score += 1
				var p_match = true
				for p_idx in range(l1.panels.size()):
					var p1 = l1.panels[p_idx]
					var p2 = l2.panels[p_idx]
					if p1.position.distance_to(p2.position) > 10.0:
						p_match = false
						break
				if p_match:
					score += 1

			var ratio = score / total
			if ratio >= 0.85: # 85%+ similarity
				sim.append({"id": levels[j]["id"], "ratio": ratio})
				handled[j] = true

		if sim.size() > 0:
			handled[i] = true
			var group = [levels[i]["id"]]
			for s in sim:
				group.append(s["id"])
			duplicates.append(group)

	print("\n--- Benzer Bolum Gruplari ---")
	if duplicates.is_empty():
		print("Hic benzer bolum bulunamadi.")
	else:
		for g in duplicates:
			var s = ""
			for id in g:
				s += str(id) + ", "
			print("Grup: " + s.substr(0, s.length() - 2))

	quit(0)
