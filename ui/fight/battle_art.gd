class_name BattleArt
extends RefCounted
## Reads data/ui/battle_presentation.json and decides how each unit looks:
## which sprite manifest unit (or the fallback sheet), which tier, which parts
## and palette. Also cuts the battle's effect sheets into SpriteFrames.
## Needs no scene.
##
## A drafted bot is the manifest's ally unit with parts and a palette picked
## from its id (SpriteManifest.ally_look), in the tier the tier rule gives.
## An enemy is drawn by, in order: SpriteManifest.for_enemy() (P4's enemy
## sprite table, used when present), the manifest unit with its enemy table id,
## a manifest unit listing that id in "enemy_ids", the "enemy_sprites" alias
## here, else the fallback sheet recolored per enemy type. Enemy tiers follow
## the fight's defense level.

const DATA_PATH := "res://data/ui/battle_presentation.json"

static var _data := {}
static var _frames := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("BattleArt: could not read %s" % DATA_PATH)
	return _data


static func reload() -> void:
	_data = {}
	_frames.clear()


static func number(key: String, fallback := 0.0) -> float:
	var node: Variant = data()
	for part in key.split("."):
		if not (node is Dictionary) or not node.has(part):
			return fallback
		node = node[part]
	return float(node) if (node is float or node is int) else fallback


static func color(name: String) -> Color:
	return FeelData.color(name)


## The enemy table id of a fighting unit: "rust_hound#2" -> "rust_hound".
static func base_id(unit_id: String) -> String:
	return unit_id.get_slice("#", 0)


## P4's enemy sprite lookup, SpriteManifest.for_enemy(enemy_id) -> {unit, tier},
## when that method exists; {} otherwise or when it knows no sprite.
static func manifest_enemy_entry(enemy_id: String) -> Dictionary:
	var script: Script = load("res://ui/common/sprite_manifest.gd")
	for m: Dictionary in script.get_script_method_list():
		if m.name == "for_enemy":
			var found: Variant = script.call("for_enemy", enemy_id)
			if found is Dictionary and SpriteManifest.unit(str(found.get("unit", ""))).get("kind", "") == "enemy":
				return found
	return {}


## The manifest unit that draws enemy `enemy_id`, or "" for the fallback.
static func enemy_unit_id(enemy_id: String) -> String:
	var entry := manifest_enemy_entry(enemy_id)
	if not entry.is_empty():
		return str(entry["unit"])
	if SpriteManifest.unit(enemy_id).get("kind", "") == "enemy":
		return enemy_id
	for id: String in SpriteManifest.unit_ids():
		var def := SpriteManifest.unit(id)
		if def.get("kind", "") == "enemy" and enemy_id in def.get("enemy_ids", []):
			return id
	var alias := str(data().get("enemy_sprites", {}).get(enemy_id, ""))
	if not alias.is_empty() and SpriteManifest.unit(alias).get("kind", "") == "enemy":
		return alias
	return ""


static func enemy_tier(defense_level: int) -> String:
	var tiers: Array = data().get("enemy_tier_by_defense_level", [])
	if tiers.is_empty():
		return BattleTierRule.tier_name(0)
	return str(tiers[clampi(defense_level, 0, tiers.size() - 1)])


## A stable seed for a unit's look: the same bot looks the same every fight.
static func look_seed(unit_id: String) -> int:
	return hash(unit_id)


## The fallback palette name for an enemy type, picked from its id.
static func fallback_palette(enemy_id: String) -> String:
	var names: Array = data().get("fallback_enemy", {}).get("palettes", {}).keys()
	names.sort()
	if names.is_empty():
		return ""
	return names[posmod(hash(enemy_id), names.size())]


## A palette dictionary ({primary, secondary, glow}) lined up with the key colors.
static func palette_colors(palette: Dictionary) -> PackedColorArray:
	var out := PackedColorArray()
	var keys: Dictionary = SpriteManifest.data().get("key_colors", {})
	for group in ["primary", "secondary", "glow"]:
		var colors: Array = palette.get(group, [])
		for i in keys.get(group, []).size():
			out.append(Color(colors[i]) if i < colors.size() else Color.MAGENTA)
	return out


## How to draw `unit`. Keys: unit_id ("" for the fallback), sheet (fallback
## only), tier, look (allies), palette (PackedColorArray, empty to keep the
## sheet's colors), glow (Color for the tier glow).
## `bot` is the drafted Bot behind an ally, or null.
static func look_for(unit: Combatant, defense_level: int, tier_rule: BattleTierRule, bot: Bot = null) -> Dictionary:
	if unit.side == Combatant.Side.PLAYER:
		var ally_id := str(data().get("ally_unit", "ally_frame"))
		var info := BattleTierRule.info_for_bot(bot) if bot != null else BattleTierRule.info_for_combatant(unit)
		var look := SpriteManifest.ally_look(ally_id, look_seed(unit.id))
		var palette := SpriteManifest.palette_colors(look.get("palette", "")) if look.get("palette", "") != "" else PackedColorArray()
		return {
			"unit_id": ally_id, "tier": tier_rule.tier_for(info), "look": look, "palette": palette,
			"glow": palette[palette.size() - 1] if not palette.is_empty() else color("sprite_glow"),
		}
	var enemy_id := base_id(unit.id)
	var tier := enemy_tier(defense_level)
	var entry := manifest_enemy_entry(enemy_id)
	if str(entry.get("tier", "")) in SpriteManifest.tiers():
		tier = str(entry["tier"])
	var manifest_id := enemy_unit_id(enemy_id)
	if not manifest_id.is_empty():
		return {"unit_id": manifest_id, "tier": tier, "look": {}, "palette": PackedColorArray(), "glow": color("enemy")}
	var fallback: Dictionary = data().get("fallback_enemy", {})
	var palette_name := fallback_palette(enemy_id)
	var palette := palette_colors(fallback.get("palettes", {}).get(palette_name, {}))
	return {
		"unit_id": "", "sheet": str(fallback.get("sheets", {}).get(tier, "")), "tier": tier, "look": {},
		"palette": palette, "glow": palette[palette.size() - 1] if not palette.is_empty() else color("enemy"),
	}


## `look` with a palette no unit in `used` (palette names) has yet, so a
## squad never shows two bots in one color while the ally has palettes left.
## Adds the palette it picked to `used`.
static func with_distinct_palette(look: Dictionary, used: Array) -> Dictionary:
	var name := str(look.get("look", {}).get("palette", ""))
	var palettes: Array = SpriteManifest.unit(str(look.get("unit_id", ""))).get("palettes", [])
	if name.is_empty() or palettes.is_empty():
		return look
	var start := palettes.find(name)
	for i in palettes.size():
		var candidate: String = palettes[(start + i) % palettes.size()]
		if not candidate in used:
			name = candidate
			break
	used.append(name)
	var out := look.duplicate(true)
	out["look"]["palette"] = name
	var colors := SpriteManifest.palette_colors(name)
	out["palette"] = colors
	out["glow"] = colors[colors.size() - 1]
	return out


## The look of the tier: plate texture path, glow alpha, pulse and scale.
static func tier_look(tier: String) -> Dictionary:
	return data().get("tier_look", {}).get(tier, {})


static func effect_names() -> Array:
	return data().get("effects", {}).keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


## SpriteFrames for an effect in "effects" (one animation named after it), or
## the sprite manifest's effect of that name, or null.
static func effect_frames(name: String) -> SpriteFrames:
	if name.is_empty():
		return null
	if _frames.has(name):
		return _frames[name]
	var spec: Dictionary = data().get("effects", {}).get(name, {})
	if spec.is_empty():
		return SpriteManifest.effect_frames(name)
	var texture: Texture2D = load(spec["sheet"])
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(name)
	frames.set_animation_speed(name, float(spec.get("fps", 12)))
	frames.set_animation_loop(name, bool(spec.get("loop", false)))
	var w := int(spec["frame_size"][0])
	var h := int(spec["frame_size"][1])
	for i in int(spec["frames"]):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * w, 0, w, h)
		frames.add_frame(name, atlas)
	_frames[name] = frames
	return frames
