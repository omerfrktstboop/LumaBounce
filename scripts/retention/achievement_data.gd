class_name AchievementData
extends Resource

@export var id := ""
@export var title_key := ""
@export var description_key := ""
@export var counter_key := ""
@export var target := 1
@export var coin_reward := 0


static func create(achievement_id: String, title: String, description: String,
		counter: String, required: int, reward: int) -> AchievementData:
	var data := AchievementData.new()
	data.id = achievement_id
	data.title_key = title
	data.description_key = description
	data.counter_key = counter
	data.target = maxi(required, 1)
	data.coin_reward = maxi(reward, 0)
	return data
