class_name DailyQuestData
extends Resource

## Gunluk gorevlerin salt-okunur veri modeli. UI ve ilerleme mantigi gorev
## turlerini metinlerden tahmin etmez; ayni katalog hem ekrani hem store'u besler.

enum Kind {
	COMPLETE_LEVELS,
	ONE_SHOT,
	BOUNCES,
	THREE_STAR,
	NO_FULL_HINT,
	BONUS_ATTEMPT,
}

@export var id := ""
@export var kind: Kind = Kind.COMPLETE_LEVELS
@export var target := 1
@export var title_key := ""
@export var analytics_type := ""


static func create(quest_id: String, quest_kind: Kind, quest_target: int,
		quest_title_key: String, quest_analytics_type: String) -> DailyQuestData:
	var quest := DailyQuestData.new()
	quest.id = quest_id
	quest.kind = quest_kind
	quest.target = maxi(quest_target, 1)
	quest.title_key = quest_title_key
	quest.analytics_type = quest_analytics_type
	return quest
