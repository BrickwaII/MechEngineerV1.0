class_name DraftCard
extends Button
## One bot in the draft: its sprite from the manifest (an ally frame with a
## look picked from the bot's id), name, personality, stats and skills. It
## flips in when the draft opens, lifts under the cursor and glows in the ally
## color when picked. Timings: data/feel/screens.json "draft".
##
## The card's content sits in `face`, which moves and scales; the Button itself
## stays put so the row's layout never shifts.

const Palette := preload("res://ui/fight/fight_palette.gd")
const ALLY_UNIT := "ally_frame"

var bot: Bot
var settings: GameSettings
## The content that flips and lifts.
var face: Control
var sprite: UnitSprite
## The badge with the pick order ("1", "2", ...), hidden when not picked.
var badge: Label

var _lift := 0.0
var _lift_tween: Tween
var _flip_tween: Tween


## A stable look seed for a bot: the same bot always looks the same.
static func look_seed(bot_id: String) -> int:
	return hash(bot_id)


func _init(p_bot: Bot = null, p_settings: GameSettings = null) -> void:
	bot = p_bot
	settings = p_settings
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	if bot != null:
		name = "Card_%s" % bot.id
		_build()
	mouse_entered.connect(_set_lifted.bind(true))
	mouse_exited.connect(_set_lifted.bind(false))
	toggled.connect(func(_on: bool) -> void: _restyle())
	resized.connect(_place_face)


## How far the card is lifted, in pixels (0 at rest, draft.lift_px when hovered).
func lift() -> float:
	return _lift


## Hides the card edge-on and flips it face-up after `delay` seconds.
func flip_in(delay: float) -> void:
	var flip := ScreenFeel.seconds("draft.flip_ms", _s())
	if flip <= 0.0:
		face.scale = Vector2.ONE
		face.modulate.a = 1.0
		return
	face.scale = Vector2(0.0, 1.0)
	face.modulate.a = 0.0
	if _flip_tween != null:
		_flip_tween.kill()
	_flip_tween = create_tween()
	_flip_tween.tween_interval(delay)
	_flip_tween.tween_callback(SoundPlayer.fire.bind(&"card_flip"))
	_flip_tween.tween_property(face, "modulate:a", 1.0, flip * 0.5)
	_flip_tween.parallel().tween_property(face, "scale:x", 1.0, flip) \
		.set_trans(FeelTween.transition("ui_pop", _s())).set_ease(Tween.EASE_OUT)


func is_flipping() -> bool:
	return _flip_tween != null and _flip_tween.is_running()


## Where the sprite sits on screen, for the snap into the squad bar.
func sprite_global_position() -> Vector2:
	return sprite.global_position


func set_pick_order(order: int) -> void:
	badge.visible = order > 0
	badge.text = str(order)


func _set_lifted(lifted: bool) -> void:
	var target := ScreenFeel.number("draft.lift_px") if lifted else 0.0
	if lifted:
		SoundPlayer.fire(&"ui_hover")
	if _lift_tween != null:
		_lift_tween.kill()
	var duration := ScreenFeel.seconds("draft.lift_ms", _s())
	if duration <= 0.0:
		_set_lift(target)
		return
	_lift_tween = create_tween()
	_lift_tween.tween_method(_set_lift, _lift, target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_lift(value: float) -> void:
	_lift = value
	_place_face()


func _place_face() -> void:
	if face == null:
		return
	face.size = size
	face.pivot_offset = size / 2.0
	face.position = Vector2(0, -_lift)


func _build() -> void:
	face = PanelContainer.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face)
	_restyle()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(col)

	var art := Control.new()
	art.name = "Art"
	art.custom_minimum_size = Vector2(0, 108)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(art)
	var plate := ColorRect.new()
	plate.color = Palette.BACKGROUND
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(plate)
	sprite = UnitSprite.new()
	sprite.settings = settings
	sprite.setup(ALLY_UNIT, str(ScreenFeel.value("draft.sprite_tier", "beginner")), SpriteManifest.ally_look(ALLY_UNIT, look_seed(bot.id)))
	sprite.scale = Vector2.ONE * ScreenFeel.number("draft.sprite_scale", 3.0)
	art.add_child(sprite)
	art.resized.connect(func() -> void: sprite.position = art.size / 2.0)
	badge = DraftScreen._label(art, "", 20, Palette.TEXT_BRIGHT)
	badge.name = "Badge"
	badge.visible = false
	badge.position = Vector2(8, 4)

	DraftScreen._label(col, bot.display_name, 20, Palette.TEXT_BRIGHT)
	DraftScreen._label(col, bot.personality.get_tag().to_upper(), 10, Palette.ACTIVE)
	var s := bot.stats
	DraftScreen._label(col, "HP %d\nATK %d   DEF %d\nSPD %d   ELA %d\nBATTERY %d" % [
		s.hp, s.attack, s.defense, s.speed, s.elasticity, s.battery_capacity], 10, Palette.TEXT)
	var skill_names := PackedStringArray()
	for skill in bot.skills:
		skill_names.append(skill.display_name)
	DraftScreen._label(col, "SKILLS", 10, Palette.TEXT_DIM)
	DraftScreen._label(col, "\n".join(skill_names), 10, Palette.TEXT)


## Picked cards get the ally border and a raised panel; the rest a plain one.
func _restyle() -> void:
	if face == null:
		return
	var picked := button_pressed
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PANEL_RAISED if picked else Palette.PANEL
	style.border_color = Palette.ALLY if picked else Palette.RULE
	style.set_border_width_all(3 if picked else 2)
	style.set_content_margin_all(12)
	face.add_theme_stylebox_override("panel", style)


func _s() -> GameSettings:
	return settings if settings else GameSettings.shared()
