class_name BattleUnitSprite
extends UnitSprite
## A UnitSprite that can also draw a sheet with no manifest entry (the
## fallback enemy) and recolor any unit with a palette. Set up from a
## BattleArt.look_for() dictionary.


func setup_look(p_look: Dictionary) -> void:
	var manifest_id := str(p_look.get("unit_id", ""))
	if manifest_id.is_empty():
		setup_sheet(str(p_look.get("sheet", "")), str(p_look.get("tier", "")))
	else:
		setup(manifest_id, str(p_look.get("tier", "")), p_look.get("look", {}))
	var palette: PackedColorArray = p_look.get("palette", PackedColorArray())
	if not palette.is_empty():
		material_swap.set_shader_parameter("targets", palette)


## Draws one sheet cut by the default layout, recolorable like an ally part.
func setup_sheet(sheet: String, p_tier: String) -> void:
	unit_id = ""
	tier = p_tier
	look = {}
	for layer in _layers:
		layer.queue_free()
	_layers.clear()
	material_swap = ShaderMaterial.new()
	material_swap.shader = SHADER
	var keys := SpriteManifest.key_colors()
	material_swap.set_shader_parameter("keys", keys)
	material_swap.set_shader_parameter("targets", keys)
	material_swap.set_shader_parameter("key_count", keys.size())
	if not sheet.is_empty() and ResourceLoader.exists(sheet):
		_add_layer(sheet)
	scale = Vector2.ONE * SpriteManifest.display_scale()
	play("idle")


func play(anim: StringName) -> void:
	if _layers.is_empty() or not _layers[0].sprite_frames.has_animation(anim):
		return
	super.play(anim)


## Holds the current frame (true) or lets the animation run (false), so units
## out of focus stand still.
func set_still(still: bool) -> void:
	for layer in _layers:
		if still:
			layer.pause()
		elif not layer.is_playing() and layer.sprite_frames.get_animation_loop(layer.animation):
			layer.play()


func is_still() -> bool:
	return not _layers.is_empty() and not _layers[0].is_playing()
