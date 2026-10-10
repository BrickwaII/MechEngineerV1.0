class_name SkillUseLedger
extends Resource
## Skill uses banked toward the next level, per bot and skill, so counts carry
## from fight to fight. Save it beside the squad; PostFight.apply() reads and
## updates it.

## "<bot id>/<skill name>" -> uses banked toward the next level step.
@export var banked: Dictionary[String, int] = {}


static func key(bot_id: String, skill_name: String) -> String:
	return "%s/%s" % [bot_id, skill_name]


func get_banked(bot_id: String, skill_name: String) -> int:
	return banked.get(key(bot_id, skill_name), 0)


func set_banked(bot_id: String, skill_name: String, uses: int) -> void:
	banked[key(bot_id, skill_name)] = uses
