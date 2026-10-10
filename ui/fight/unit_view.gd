extends Control
## The stage one unit stands on inside its card: the tier glow behind it, the
## tier plate under it, the animated sprite, and a target reticle over it
## while the unit can be targeted. Moves (lunge, recoil, knockback) are an
## offset from the sprite's resting spot, so the card layout never shifts.

const STAGE_SIZE := Vector2(104, 104)
const RETICLE := preload("res://assets/fight/icons/target_reticle.png")

var sprite: BattleUnitSprite
var glow: Sprite2D
var plate: Sprite2D
var reticle: Sprite2D
var look := {}
var tier := ""
var is_enemy := false
var guarded := false
var down := false
var settings: GameSettings
## Offset from the resting spot, in screen pixels.
var motion_offset := Vector2.ZERO:
	set(v):
		motion_offset = v.round()
		_place()

var _glow_alpha := 0.0
var _glow_pulse := 0.0
var _clock := 0.0
var _still := false


func _init() -> void:
	custom_minimum_size = STAGE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_look: Dictionary, p_is_enemy: bool) -> void:
	look = p_look
	tier = str(p_look.get("tier", ""))
	is_enemy = p_is_enemy
	var scale_px := float(SpriteManifest.display_scale())
	var tier_look := BattleArt.tier_look(tier)
	glow = Sprite2D.new()
	glow.name = "Glow"
	glow.texture = load(str(BattleArt.data().get("glow_texture", "res://assets/fight/tiers/glow.png")))
	glow.scale = Vector2.ONE * scale_px * float(tier_look.get("glow_scale", 1.0))
	_glow_alpha = float(tier_look.get("glow_alpha", 0.0))
	_glow_pulse = float(tier_look.get("glow_pulse", 0.0))
	glow.modulate = Color(p_look.get("glow", Color.WHITE), _glow_alpha)
	glow.visible = _glow_alpha > 0.0
	add_child(glow)
	plate = Sprite2D.new()
	plate.name = "Plate"
	var plate_path := str(tier_look.get("plate", ""))
	if not is_enemy and ResourceLoader.exists(plate_path):
		plate.texture = load(plate_path)
	plate.scale = Vector2.ONE * scale_px
	add_child(plate)
	sprite = BattleUnitSprite.new()
	sprite.name = "Sprite"
	sprite.settings = settings
	add_child(sprite)
	sprite.setup_look(p_look)
	# The plate takes the bot's palette too, so trims match the paint.
	plate.material = sprite.material_swap
	sprite.animation_finished.connect(_on_animation_finished)
	reticle = Sprite2D.new()
	reticle.name = "Reticle"
	reticle.texture = RETICLE
	reticle.scale = Vector2.ONE * 4.0
	reticle.visible = false
	add_child(reticle)
	_place()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()


func _process(delta: float) -> void:
	_clock += delta
	if glow != null and glow.visible and _glow_pulse > 0.0 and not _still:
		var period := maxf(0.1, BattleArt.number("glow_pulse_ms", 1600.0) / 1000.0)
		var a := _glow_alpha + _glow_pulse * sin(TAU * _clock / period)
		glow.modulate.a = clampf(a, 0.0, 1.0)
	if reticle != null and reticle.visible:
		reticle.scale = Vector2.ONE * (4.0 if fmod(_clock, 0.6) < 0.3 else 5.0)


## Where effects aimed at this unit land, in global coordinates.
func center_global() -> Vector2:
	return get_global_transform() * (size / 2.0)


func play(anim: StringName) -> void:
	if sprite != null:
		sprite.play(anim)


## The pose the unit holds between actions.
func rest_animation() -> StringName:
	if down:
		return &"down"
	return &"guard" if guarded else &"idle"


## Guard pose while guarded, the down animation once when it goes down.
func set_state(p_guarded: bool, p_down: bool) -> void:
	var changed := p_guarded != guarded or p_down != down
	guarded = p_guarded
	var went_down := p_down and not down
	down = p_down
	if went_down:
		play(&"down")
		glow.visible = false
	elif changed and not down:
		play(rest_animation())


## Holds the unit still while another unit is the focus.
func set_still(still: bool) -> void:
	_still = still
	if sprite != null and not down:
		sprite.set_still(still)


func set_flash(amount: float) -> void:
	if sprite != null:
		sprite.set_flash(amount)


func set_targeted(on: bool, color := Color.WHITE) -> void:
	if reticle != null:
		reticle.visible = on and not down
		reticle.modulate = color


func _on_animation_finished(anim: StringName) -> void:
	if anim == &"down":
		return
	if anim != rest_animation():
		play(rest_animation())


func _place() -> void:
	if sprite == null:
		return
	var center := (size / 2.0).round()
	var scale_px := float(SpriteManifest.display_scale())
	sprite.position = center + motion_offset
	glow.position = center + motion_offset
	# The plate sits under the feet: the frame's bottom rows.
	plate.position = center + Vector2(0, 14 * scale_px) + Vector2(motion_offset.x, 0)
	reticle.position = center
