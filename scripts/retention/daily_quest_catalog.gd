class_name DailyQuestCatalog
extends RefCounted

## V1 gorev havuzu. Her gun sabit bir hash ile uc farkli gorev secilir; ayni
## tarih her acilista ayni sirayi verir ve runtime AI/ag cagrisina ihtiyac duymaz.

const QUESTS_PER_DAY := 3


static func all() -> Array[DailyQuestData]:
	return [
		DailyQuestData.create("complete_3", DailyQuestData.Kind.COMPLETE_LEVELS, 3,
			"3 bölüm tamamla", "complete_levels"),
		DailyQuestData.create("one_shot_1", DailyQuestData.Kind.ONE_SHOT, 1,
			"Bir bölümü tek atışta tamamla", "one_shot"),
		DailyQuestData.create("bounce_25", DailyQuestData.Kind.BOUNCES, 25,
			"Toplam 25 sekme yap", "bounces"),
		DailyQuestData.create("three_star_1", DailyQuestData.Kind.THREE_STAR, 1,
			"Bir bölümü 3 yıldızla tamamla", "three_star"),
		DailyQuestData.create("no_full_hint_3", DailyQuestData.Kind.NO_FULL_HINT, 3,
			"Tam rota kullanmadan 3 bölüm tamamla", "no_full_hint"),
		DailyQuestData.create("bonus_attempt_1", DailyQuestData.Kind.BONUS_ATTEMPT, 1,
			"Bir bonus bölüm dene", "bonus_attempt"),
	]


static func find(quest_id: String) -> DailyQuestData:
	for quest in all():
		if quest.id == quest_id:
			return quest
	return null


static func ids_for_date(date_key: String) -> PackedStringArray:
	var pool := all()
	var ids := PackedStringArray()
	if pool.is_empty():
		return ids
	var index := stable_hash(date_key + ":quests") % pool.size()
	# 5, alti elemanli havuzla aralarinda asal; tekrar etmeden tum havuzu gezer.
	for _slot in range(mini(QUESTS_PER_DAY, pool.size())):
		ids.append(pool[index].id)
		index = (index + 5) % pool.size()
	return ids


static func stable_hash(value: String) -> int:
	# String.hash surumler arasinda degisebilir. Basit FNV-1a ile tarih secimi
	# oyun guncellense bile ayni kalir.
	var result := 2166136261
	for index in value.length():
		result = result ^ value.unicode_at(index)
		result = int((result * 16777619) & 0x7fffffff)
	return result
