class_name SkillFx
extends RefCounted
## The look and sound of each skill, and how they grow with its level, from
## data/ui/battle_presentation.json ("skills", "skill_for", "level_steps").
## Needs no scene: the presenter asks for a skill's fx and plays it.
##
##   var fx := SkillFx.for_skill(unit.skill("heavy_strike"))
##   fx.fx_id        # "overcharge_shot" for a bot that calls it that
##   fx.scale        # grows with the level, in steps from level_steps
##   SkillFx.sounds(fx)   # the skill's sound plus its level's layers
##
## Every level keeps the same timing (data/feel/feel.json attack parts): a
## higher level is bigger, brighter, has more particles and projectiles, a
## heavier impact and a fuller sound, never a longer animation.

const MOTIONS: Array[String] = ["lunge", "shoot", "sweep", "slam", "blast", "cast", "guard"]
## Motions that fire a projectile, so "extra" adds projectiles.
const SHOOTING: Array[String] = ["shoot", "blast"]


static func skills() -> Dictionary:
	return BattleArt.data().get("skills", {})


static func spec(fx_id: String) -> Dictionary:
	return skills().get(fx_id, {})


## A name as a key: "Overcharge Shot" -> "overcharge_shot".
static func slug(text: String) -> String:
	return text.strip_edges().to_lower().replace(" ", "_").replace("-", "_")


## The fx id for a unit's skill: by its own name, then its id, then its effect.
static func fx_id_for(skill: CombatSkill) -> String:
	if skill == null:
		return ""
	var by_name := slug(skill.display_name)
	if skills().has(by_name):
		return by_name
	var rules: Dictionary = BattleArt.data().get("skill_for", {})
	var by_id := str(rules.get("by_id", {}).get(skill.id, ""))
	if skills().has(by_id):
		return by_id
	return str(rules.get("by_effect", {}).get(skill.effect, ""))


## Levels with their own step; a higher level uses the last one.
static func max_level() -> int:
	return maxi(1, BattleArt.data().get("level_steps", []).size())


## The level step for `level` (1-based, clamped to 1..max_level()).
static func step(level: int) -> Dictionary:
	var steps: Array = BattleArt.data().get("level_steps", [])
	if steps.is_empty():
		return {"scale": 1.0, "brightness": 1.0, "particles": 0, "extra": 0, "impact": "light", "layers": []}
	return steps[clampi(level, 1, steps.size()) - 1]


## The full fx for a skill at its level: the skill's look merged with its
## level step, plus fx_id, level and projectiles.
static func for_skill(skill: CombatSkill) -> Dictionary:
	return for_fx(fx_id_for(skill), skill.fx_level if skill != null else 1)


static func for_fx(fx_id: String, level: int) -> Dictionary:
	var out := spec(fx_id).duplicate(true)
	if out.is_empty():
		out = {"motion": "lunge", "charge_effect": "", "projectile": "", "impact_effect": "hit_spark",
			"color": "text_bright", "accent": "sprite_spark", "sound": "", "impact_sound": "hit_light"}
	out.merge(step(level), true)
	out["fx_id"] = fx_id
	out["level"] = clampi(level, 1, max_level())
	out["projectiles"] = projectile_count(out)
	return out


## How many projectiles a shot fires: one, plus the step's extra for
## shooting motions; 0 for skills with no projectile.
static func projectile_count(fx: Dictionary) -> int:
	if str(fx.get("projectile", "")).is_empty():
		return 0
	if str(fx.get("motion", "")) in SHOOTING:
		return 1 + int(fx.get("extra", 0))
	return 1


## The sounds to start at the strike: the skill's own, then its level's layers.
static func sounds(fx: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if not str(fx.get("sound", "")).is_empty():
		out.append(StringName(fx["sound"]))
	for layer: Variant in fx.get("layers", []):
		out.append(StringName(layer))
	return out


## The hit pause of a landed hit: "heavy" for big hits or heavy steps.
static func impact_kind(fx: Dictionary, big_hit: bool) -> String:
	return "heavy" if big_hit or str(fx.get("impact", "light")) == "heavy" else "light"


## True when a hit of `damage` on a unit with `max_hp` counts as big (the
## heavy pause and the small shake), or when it downs the unit.
static func is_big_hit(damage: int, max_hp: int, downs: bool) -> bool:
	if downs:
		return true
	return max_hp > 0 and float(damage) >= float(max_hp) * BattleArt.number("big_hit_share", 0.25)


## The effect tint at the step's brightness: brighter levels lean to white.
static func tint(fx: Dictionary, key := "color") -> Color:
	var base := BattleArt.color(str(fx.get(key, "text_bright")))
	return base.lerp(Color.WHITE, clampf(float(fx.get("brightness", 1.0)) - 1.0, 0.0, 1.0))
