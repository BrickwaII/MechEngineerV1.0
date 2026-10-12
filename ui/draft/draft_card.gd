class_name DraftCard
extends Button
## One bot in the draft: its sprite from the manifest (an ally frame with a
## look picked from the bot's id), name, personality (its tag and hexagon),
## stats and skills. It
## flips in when the draft opens, lifts under the cursor and glows in the ally
## color when picked. Timings: data/feel/screens.json "draft".
##
## The card's content sits in `face`, which moves and scales; the Button itself
## stays put so the row's layout never shifts.

const Palette := preload("res://ui/fight/fight_palette.gd")
const ALLY_UNIT := "ally_frame"

var bot: Bot
var settings: GameSettings
## The fight's combat tuning (with the run's fight variants), so each skill
## row shows the cost and numbers the battle will use.
var combat_tuning: CombatTuning
## The content that flips and lifts.
var face: Control
var sprite: UnitSprite
## The badge with the pick order ("1", "2", ...), hidden when not picked.
var badge: Label
## The personality's trait icon; null for a balanced bot.
var trait_icon: IconStat
## Stat icon id ("hp", "atk", ...) -> its IconStat.
var stat_icons: Dictionary[String, IconStat] = {}

var _lift := 0.0
var _lift_tween: Tween
var _flip_tween: Tween


## A stable look seed for a bot: the same bot always looks the same.
static func look_seed(bot_id: String) -> int:
	return hash(bot_id)


func _init(p_bot: Bot = null, p_settings: GameSettings = null, p_tuning: CombatTuning = null) -> void:
	bot = p_bot
	settings = p_settings
	combat_tuning = p_tuning if p_tuning != null else CombatTuning.load_default()
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
	# The personality as its trait icon (the word is in the tooltip and on the
	# hexagon); a balanced bot, with no trait icon, keeps the word.
	var tag := bot.personality.get_tag()
	if UiIcons.has("trait_%s" % tag):
		trait_icon = IconStat.make("trait_%s" % tag)
		trait_icon.name = "Trait"
		trait_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(trait_icon)
	else:
		DraftScreen._label(col, tag.to_upper(), 10, Palette.ACTIVE)
	var hex := PersonalityHexagon.new()
	hex.name = "Hexagon"
	var hex_size: Array = ScreenFeel.value("readout.draft_hex_size", [150, 118])
	hex.custom_minimum_size = Vector2(hex_size[0], hex_size[1])
	hex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hex.min_extent = ScreenFeel.number("readout.hex_min_extent", 0.5)
	hex.font_size = 8
	hex.show_ends(bot.personality.get_ends())
	col.add_child(hex)
	# Stats as icons and numbers (ui/README.md rule 1).
	var s := bot.stats
	var grid := GridContainer.new()
	grid.name = "Stats"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(grid)
	for pair in [["hp", s.hp], ["atk", s.attack], ["def", s.defense],
			["spd", s.speed], ["ela", s.elasticity], ["battery", s.battery_capacity]]:
		var stat := IconStat.make(pair[0], pair[1])
		stat_icons[pair[0]] = stat
		grid.add_child(stat)
	# Skills as the battle will show them: the Energy cost, the name and rank,
	# and the effect with this bot's true numbers ("Deal 9. Pierce 20%.").
	var skills := VBoxContainer.new()
	skills.name = "Skills"
	skills.add_theme_constant_override("separation", 4)
	skills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(skills)
	for face: Dictionary in skill_faces(bot, combat_tuning):
		var row := HBoxContainer.new()
		row.name = "Skill_%s" % face.id
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		skills.add_child(row)
		var title: String = face.name if face.rank.is_empty() else "%s %s" % [face.name, face.rank]
		UiTooltip.attach(row, title, face.effect, "Energy: %d" % face.cost, "energy")
		var cost := IconStat.make("energy", face.cost)
		cost.custom_minimum_size.x = 40
		row.add_child(cost)
		# Name and effect share one line, so the card keeps its height.
		var name_label := DraftScreen._label(row, title, 10, Palette.TEXT_BRIGHT)
		name_label.name = "Name"
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var effect := UiGlossary.rich(face.effect, ScreenTheme.size(10), Palette.TEXT)
		effect.name = "Effect"
		# One line: a wrapping label in a row asks for far more height than it uses.
		effect.autowrap_mode = TextServer.AUTOWRAP_OFF
		effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		effect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(effect)


## The skills `bot` fights with, in menu order, as the battle builds them
## (SquadSkills: its own skills, plus the basic attack when it has no free
## one): [{id, name, rank, effect, cost}], with the effect worked out from the
## bot's attack (BattleScreen.skill_card_face).
static func skill_faces(p_bot: Bot, tuning: CombatTuning) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var member := p_bot.to_summary()
	var overrides := SquadSkills.overrides_for(member, tuning)
	for id in SquadSkills.ids_for(member, tuning):
		var o: Dictionary = overrides.get(id, {})
		var skill := tuning.skill_at(id, int(o.get("level", 1)), String(o.get("name", "")))
		if skill == null:
			continue
		var face := BattleScreen.skill_card_face(skill, member.stats.attack)
		face["id"] = id
		face["cost"] = skill.energy_cost
		out.append(face)
	return out


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
