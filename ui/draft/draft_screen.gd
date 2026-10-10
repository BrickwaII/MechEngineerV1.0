class_name DraftScreen
extends Control
## Squad draft: shows the seeded draft as cards, lets the player pick
## squad_size bots by clicking them, and emits squad_chosen on START FIGHT.
## Draft and squad sizes come from data/bot_data/ through BotTuning.

const Palette := preload("res://ui/fight/fight_palette.gd")
const FightTheme := preload("res://ui/fight/fight_theme.gd")

signal squad_chosen(squad: Array[SquadMemberSummary])

## Set before the screen enters the tree.
var draft_seed := 0
var bot_tuning: BotTuning
var picker: DraftPicker

var cards: Dictionary[String, Button] = {}
var start_button: Button
var count_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = FightTheme.make()
	if bot_tuning == null:
		bot_tuning = BotTuning.load_default()
	picker = DraftPicker.new(bot_tuning, draft_seed)
	_build_layout()
	refresh()


func toggle(bot_id: String) -> String:
	var problem := picker.toggle(bot_id)
	refresh()
	return problem


func start() -> void:
	if picker.can_start():
		squad_chosen.emit(picker.summaries())


func refresh() -> void:
	for bot_id in cards:
		cards[bot_id].button_pressed = picker.is_picked(bot_id)
	count_label.text = "%d / %d picked" % [picker.picked_ids().size(), picker.squad_size()]
	start_button.disabled = not picker.can_start()


func _build_layout() -> void:
	var back := ColorRect.new()
	back.color = Palette.BACKGROUND
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 20
	root.offset_right = -24
	root.offset_bottom = -20
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	_label(root, "DRAFT YOUR SQUAD", 26, Palette.TEXT_BRIGHT)
	_label(root, "Pick %d of these %d bots, then start the fight. Click a card to pick or drop it." % [
		picker.squad_size(), picker.bots().size()], 14, Palette.TEXT_DIM)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	for bot in picker.bots():
		var card := _card(bot)
		row.add_child(card)
		cards[bot.id] = card

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)
	count_label = _label(footer, "", 16, Palette.TEXT)
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "START FIGHT"
	start_button.custom_minimum_size = Vector2(200, 44)
	start_button.pressed.connect(start)
	footer.add_child(start_button)


func _card(bot: Bot) -> Button:
	var card := Button.new()
	card.name = "Card_%s" % bot.id
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	card.add_theme_stylebox_override("normal", _card_style(Palette.PANEL, Palette.RULE))
	card.add_theme_stylebox_override("hover", _card_style(Palette.PANEL_RAISED, Palette.TEXT_DIM))
	card.add_theme_stylebox_override("pressed", _card_style(Palette.PANEL_RAISED, Palette.ALLY))
	card.add_theme_stylebox_override("hover_pressed", _card_style(Palette.PANEL_RAISED, Palette.ALLY))
	card.pressed.connect(toggle.bind(bot.id))

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 12
	col.offset_top = 12
	col.offset_right = -12
	col.offset_bottom = -12
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var swatch := ColorRect.new()
	swatch.color = Palette.ALLY
	swatch.custom_minimum_size = Vector2(40, 40)
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(swatch)
	_label(col, bot.display_name, 20, Palette.TEXT_BRIGHT)
	_label(col, bot.personality.get_tag().to_upper(), 12, Palette.ACTIVE)
	var s := bot.stats
	_label(col, "HP %d\nATK %d   DEF %d\nSPD %d   ELA %d\nBATTERY %d" % [
		s.hp, s.attack, s.defense, s.speed, s.elasticity, s.battery_capacity], 14, Palette.TEXT)
	var skill_names := PackedStringArray()
	for skill in bot.skills:
		skill_names.append(skill.display_name)
	_label(col, "SKILLS", 11, Palette.TEXT_DIM)
	var skills_label := _label(col, "\n".join(skill_names), 13, Palette.TEXT)
	skills_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return card


static func _card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


static func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
