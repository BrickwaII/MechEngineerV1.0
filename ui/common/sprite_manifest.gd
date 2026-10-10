class_name SpriteManifest
extends RefCounted
## Reads data/feel/sprite_manifest.json: which sheets draw each unit, in which
## tier, and how sheets are cut into animations. Format: assets/README.md.

const ANIMATIONS := ["idle", "windup", "attack", "hit", "guard", "heal", "down"]

static var _frames_cache := {}


static func data() -> Dictionary:
	return FeelData.manifest()


static func tiers() -> Array:
	return data().get("tiers", [])


static func unit_ids() -> Array:
	return data().get("units", {}).keys()


static func unit(id: String) -> Dictionary:
	return data().get("units", {}).get(id, {})


static func is_ally(id: String) -> bool:
	return unit(id).get("kind", "") == "ally"


static func frame_size(id := "") -> Vector2i:
	var size: Array = unit(id).get("frame_size", data().get("frame_size", [32, 32]))
	return Vector2i(int(size[0]), int(size[1]))


## The animation layout for a unit: its own when it overrides one, else the default.
static func animations(id := "") -> Dictionary:
	return unit(id).get("animations", data().get("animations", {}))


static func display_scale() -> int:
	return int(data().get("display_scale", 3))


## Every sheet path a unit uses, in every tier and part variant.
static func sheets(id: String) -> Array[String]:
	var out: Array[String] = []
	var def := unit(id)
	if def.has("sheets"):
		for tier: String in def["sheets"]:
			out.append(def["sheets"][tier])
	for part: String in def.get("parts", {}):
		for variant: String in def["parts"][part]:
			for tier: String in def["parts"][part][variant]:
				out.append(def["parts"][part][variant][tier])
	return out


## An ally's look picked from `look_seed`: one variant per part and a palette.
## The same seed always gives the same look. Enemies get {}.
static func ally_look(id: String, look_seed: int) -> Dictionary:
	var def := unit(id)
	if def.get("kind", "") != "ally":
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed
	var parts := {}
	for layer: String in def.get("layers", []):
		var variants: Array = def["parts"][layer].keys()
		variants.sort()
		parts[layer] = variants[rng.randi_range(0, variants.size() - 1)]
	var palettes: Array = def.get("palettes", [])
	return {"parts": parts, "palette": palettes[rng.randi_range(0, palettes.size() - 1)] if palettes else ""}


## The key colors in shader order: primary ramp, secondary ramp, glow.
static func key_colors() -> PackedColorArray:
	var out := PackedColorArray()
	var keys: Dictionary = data().get("key_colors", {})
	for group in ["primary", "secondary", "glow"]:
		for name: String in keys.get(group, []):
			out.append(FeelData.color(name))
	return out


## A palette's colors lined up with key_colors().
static func palette_colors(name: String) -> PackedColorArray:
	var out := PackedColorArray()
	var palette: Dictionary = data().get("ally_palettes", {}).get(name, {})
	var keys: Dictionary = data().get("key_colors", {})
	for group in ["primary", "secondary", "glow"]:
		var colors: Array = palette.get(group, [])
		for i in keys.get(group, []).size():
			out.append(Color(colors[i]) if i < colors.size() else Color.MAGENTA)
	return out


## The sheet that draws `layer` of an ally (or the whole enemy when layer is "").
static func sheet_for(id: String, tier: String, layer := "", variant := "") -> String:
	var def := unit(id)
	if layer.is_empty():
		return def.get("sheets", {}).get(tier, "")
	return def.get("parts", {}).get(layer, {}).get(variant, {}).get(tier, "")


## Cuts one sheet into SpriteFrames using the unit's animation layout.
## Cached per sheet path.
static func sprite_frames(sheet_path: String, id := "") -> SpriteFrames:
	if _frames_cache.has(sheet_path):
		return _frames_cache[sheet_path]
	var texture: Texture2D = load(sheet_path)
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var size := frame_size(id)
	var layout := animations(id)
	for anim: String in layout:
		var spec: Dictionary = layout[anim]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(spec.get("fps", 8)))
		frames.set_animation_loop(anim, bool(spec.get("loop", false)))
		for i in int(spec.get("frames", 1)):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * size.x, int(spec.get("row", 0)) * size.y, size.x, size.y)
			frames.add_frame(anim, atlas)
	_frames_cache[sheet_path] = frames
	return frames


## SpriteFrames for an effect in the manifest's "effects" (one row of frames).
static func effect_frames(name: String) -> SpriteFrames:
	var spec: Dictionary = data().get("effects", {}).get(name, {})
	var key: String = "effect:" + name
	if spec.is_empty():
		return null
	if _frames_cache.has(key):
		return _frames_cache[key]
	var texture: Texture2D = load(spec["sheet"])
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(name)
	frames.set_animation_speed(name, float(spec.get("fps", 12)))
	frames.set_animation_loop(name, false)
	var w := int(spec["frame_size"][0])
	var h := int(spec["frame_size"][1])
	for i in int(spec["frames"]):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * w, 0, w, h)
		frames.add_frame(name, atlas)
	_frames_cache[key] = frames
	return frames
