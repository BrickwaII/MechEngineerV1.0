class_name UnitSprite
extends Node2D
## Draws one unit from the sprite manifest. An ally is stacked from its part
## layers (legs, body, head, arm) and recolored by the palette swap shader; an
## enemy is one sheet. All layers play the same animation in step.
##
##     var sprite := UnitSprite.new()
##     sprite.setup("ally_frame", "medium", SpriteManifest.ally_look("ally_frame", bot_seed))
##     sprite.play("attack")
##
## Animation speed follows GameSettings; with "skip" an animation jumps to its
## last frame and finishes at once.

signal animation_finished(anim: StringName)

const SHADER := preload("res://ui/common/palette_swap.gdshader")

var unit_id := ""
var tier := ""
var look := {}
var settings: GameSettings
var material_swap: ShaderMaterial

var _layers: Array[AnimatedSprite2D] = []


func setup(p_unit_id: String, p_tier: String, p_look: Dictionary = {}) -> void:
	unit_id = p_unit_id
	tier = p_tier
	look = p_look
	for layer in _layers:
		layer.queue_free()
	_layers.clear()
	material_swap = ShaderMaterial.new()
	material_swap.shader = SHADER
	var keys := SpriteManifest.key_colors()
	var targets := keys
	if SpriteManifest.is_ally(unit_id):
		var palette: String = look.get("palette", "")
		if not palette.is_empty():
			targets = SpriteManifest.palette_colors(palette)
		var def := SpriteManifest.unit(unit_id)
		for layer: String in def.get("layers", []):
			var variant: String = look.get("parts", {}).get(layer, def["parts"][layer].keys()[0])
			_add_layer(SpriteManifest.sheet_for(unit_id, tier, layer, variant))
	else:
		_add_layer(SpriteManifest.sheet_for(unit_id, tier))
	material_swap.set_shader_parameter("keys", keys)
	material_swap.set_shader_parameter("targets", targets)
	material_swap.set_shader_parameter("key_count", keys.size())
	scale = Vector2.ONE * SpriteManifest.display_scale()
	play("idle")


func layer_count() -> int:
	return _layers.size()


func current_animation() -> StringName:
	return _layers[0].animation if not _layers.is_empty() else &""


func current_frame() -> int:
	return _layers[0].frame if not _layers.is_empty() else 0


func play(anim: StringName) -> void:
	var s := settings if settings else GameSettings.shared()
	for layer in _layers:
		layer.speed_scale = maxf(s.speed_multiplier(), 1.0)
		layer.play(anim)
	if s.skips_animations() and not _layers.is_empty():
		var last := _layers[0].sprite_frames.get_frame_count(anim) - 1
		for layer in _layers:
			layer.pause()
			layer.frame = last
		if not _layers[0].sprite_frames.get_animation_loop(anim):
			animation_finished.emit.call_deferred(anim)


## Shows a frame without playing, for previews and screenshots.
func show_frame(anim: StringName, frame: int) -> void:
	for layer in _layers:
		layer.animation = anim
		layer.frame = frame
		layer.pause()


## 0..1 mix toward white, for hit flashes.
func set_flash(amount: float) -> void:
	material_swap.set_shader_parameter("flash", clampf(amount, 0.0, 1.0))


func _add_layer(sheet: String) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = SpriteManifest.sprite_frames(sheet, unit_id)
	sprite.material = material_swap
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	if _layers.is_empty():
		sprite.animation_finished.connect(func() -> void: animation_finished.emit(sprite.animation))
	_layers.append(sprite)
