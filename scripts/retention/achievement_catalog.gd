class_name AchievementCatalog
extends RefCounted


static func all() -> Array[AchievementData]:
	return [
		AchievementData.create("one_shot_10", "Keskin Nişancı",
			"10 farklı tamamlamayı tek atışta yap", "one_shots", 10, 2),
		AchievementData.create("complete_100", "Yüzlük Seri",
			"100 kampanya bölümünü tamamla", "campaign_completions", 100, 5),
		AchievementData.create("bounce_1000", "Sekme Ustası",
			"Toplam 1000 sekme yap", "bounces", 1000, 3),
		AchievementData.create("three_star_25", "Kusursuz Rota",
			"25 farklı tamamlamada 3 yıldız kazan", "three_stars", 25, 3),
		AchievementData.create("all_worlds", "Tüm Dünyalar",
			"Üç dünyanın tamamını aç", "worlds_unlocked", 1, 5),
	]


static func find(achievement_id: String) -> AchievementData:
	for achievement in all():
		if achievement.id == achievement_id:
			return achievement
	return null
