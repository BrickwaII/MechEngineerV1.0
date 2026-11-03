class_name BattleModeSetup
extends Control
## Battle Mode's first screen: pick a length (Gauntlet or Endless) and a squad
## (a preset from data/battle_mode/battle_mode.json, or a fresh draft), then
## START. Choices are card buttons (ui/README.md rule 11: borders mean you can
## click); each card's tooltip lists what it holds. Home goes back to the menu.

## START with the chosen length id and squad: a preset id, or DRAFT.
signal started(length_id: String, squad_id: String)
signal home_requested

const DRAFT := "draft"
const CARD_SIZE := Vector2(232, 176)
const LENGTH_CARD_SIZE := Vector2(360, 112)

var tuning: BattleModeTuning
var bot_tuning: BotTuning
var length_id := ""
var squad_id := ""
## Length id -> its card; squad id (or DRAFT) -> its card.
var length_cards: Dictionary[String, Button] = {}
var squad_cards: Dictionary[String, Button] = {}
var start_button: ActionButton
var home_button: ActionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ScreenTheme.theme()
	if tuning == null:
		tuning = BattleModeTuning.load_default()
	if bot_tuning == null:
		bot_tuning = BotTuning.load_default()
	if length_id.is_empty() and not tuning.lengths.is_empty():
		length_id = tuning.lengths.keys()[0]
	if squad_id.is_empty():
		squad_id = tuning.squads[0].id if not tuning.squads.is_empty() else DRAFT
	_build()
	refresh()


func choose_length(id: String) -> void:
	length_id = id
	SoundPlayer.fire(&"ui_select")
	refresh()


func choose_squad(id: String) -> void:
	squad_id = id
	SoundPlayer.fire(&"ui_select")
	refresh()


func start() -> void:
	SoundPlayer.fire(&"ui_confirm")
	started.emit(length_id, squad_id)


func refresh() -> void:
	for id in length_cards:
		length_cards[id].set_pressed_no_signal(id == length_id)
	for id in squad_cards:
		squad_cards[id].set_pressed_no_signal(id == squad_id)


func _build() -> void:
	var back := ColorRect.new()
	back.color = FeelData.color("background")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var page := UiStyle.column("m")
	page.name = "Page"
	center.add_child(page)
	var title := UiStyle.label("BATTLE MODE", "title", "title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)
	var line := UiStyle.label("Fight after fight. Your bots grow; each fight asks more of them.", "text_quiet")
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(line)

	page.add_child(UiStyle.caption(UiStyle.label("LENGTH")))
	var lengths := UiStyle.row("m")
	lengths.name = "Lengths"
	lengths.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(lengths)
	var length_group := ButtonGroup.new()
	for id in tuning.lengths:
		var card := _length_card(tuning.lengths[id], length_group)
		lengths.add_child(card)
		length_cards[id] = card

	page.add_child(UiStyle.caption(UiStyle.label("SQUAD")))
	var squads := UiStyle.row("m")
	squads.name = "Squads"
	squads.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(squads)
	var squad_group := ButtonGroup.new()
	for p in tuning.squads:
		var card := _preset_card(p, squad_group)
		squads.add_child(card)
		squad_cards[p.id] = card
	var draft := _card("SquadCard_draft", CARD_SIZE, squad_group)
	var draft_face := _face(draft)
	var art := EntryTile.icon_art("new", 5)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	draft_face.add_child(art)
	draft_face.add_child(_centered(UiStyle.label("Draft", "title")))
	draft_face.add_child(_centered(UiStyle.label("Pick %d of %d new bots." % [bot_tuning.squad_size, bot_tuning.draft_size], "text_quiet")))
	UiTooltip.attach(draft, "Draft", "Draft a new squad, as at the start of a run.")
	draft.pressed.connect(choose_squad.bind(DRAFT))
	squads.add_child(draft)
	squad_cards[DRAFT] = draft

	var actions := UiStyle.row("m")
	actions.name = "Actions"
	page.add_child(actions)
	home_button = ActionButton.make("action_home", "Home")
	home_button.name = "HomeButton"
	home_button.pressed.connect(func() -> void: home_requested.emit())
	actions.add_child(home_button)
	actions.add_child(UiStyle.spring())
	start_button = ActionButton.make("action_attack", "Start")
	start_button.name = "StartButton"
	start_button.pressed.connect(start)
	actions.add_child(start_button)


func _length_card(l: BattleModeTuning.Length, group: ButtonGroup) -> Button:
	var card := _card("LengthCard_%s" % l.id, LENGTH_CARD_SIZE, group)
	var face := _face(card)
	var head := UiStyle.row("s")
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(head)
	head.add_child(UiStyle.label(l.name, "title"))
	var fights := IconStat.make("fights_won", "∞" if l.is_endless() else str(l.fights),
		"Fights in the run." if not l.is_endless() else "No end: fight until the squad falls.")
	fights.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(fights)
	var desc := _centered(UiStyle.label(l.description, "text_quiet"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	face.add_child(desc)
	UiTooltip.attach(card, l.name, l.description)
	card.pressed.connect(choose_length.bind(l.id))
	return card


func _preset_card(p: BattleModeTuning.SquadPreset, group: ButtonGroup) -> Button:
	var card := _card("SquadCard_%s" % p.id, CARD_SIZE, group)
	var face := _face(card)
	var squad := BattleModeRun.preset_squad(p.id, tuning, bot_tuning)
	var portraits := UiStyle.row("xs")
	portraits.alignment = BoxContainer.ALIGNMENT_CENTER
	portraits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(portraits)
	var lines := PackedStringArray()
	for bot in squad.get_fielded():
		var look := {"unit_id": DraftCard.ALLY_UNIT, "tier": "beginner",
			"look": SpriteManifest.ally_look(DraftCard.ALLY_UNIT, DraftCard.look_seed(bot.id))}
		var portrait := UnitPortrait.make(look, false, 56)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portraits.add_child(portrait)
		var skills := PackedStringArray()
		for s in bot.skills:
			skills.append(s.display_name)
		lines.append("%s: HP %d, ATK %d, DEF %d, SPD %d. %s" % [
			bot.display_name, bot.stats.hp, bot.stats.attack, bot.stats.defense, bot.stats.speed, ", ".join(skills)])
	face.add_child(_centered(UiStyle.label(p.name, "title")))
	var desc := _centered(UiStyle.label(p.description, "text_quiet"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	face.add_child(desc)
	UiTooltip.attach(card, p.name, p.description, "\n".join(lines))
	card.pressed.connect(choose_squad.bind(p.id))
	return card


func _card(node_name: String, size: Vector2, group: ButtonGroup) -> Button:
	var card := Button.new()
	card.name = node_name
	card.toggle_mode = true
	card.button_group = group
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = size
	card.clip_contents = true
	card.add_theme_stylebox_override("normal", UiStyle.panel("card"))
	card.add_theme_stylebox_override("hover", UiStyle.panel("card", true))
	var chosen := UiStyle.panel("card", true)
	chosen.border_color = UiStyle.role("interactive")
	chosen.set_border_width_all(4)
	card.add_theme_stylebox_override("pressed", chosen)
	card.add_theme_stylebox_override("hover_pressed", chosen)
	return card


func _face(card: Button) -> VBoxContainer:
	var face := UiStyle.column("xs")
	face.name = "Face"
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := float(UiStyle.space("s"))
	face.offset_left = pad
	face.offset_top = pad
	face.offset_right = -pad
	face.offset_bottom = -pad
	face.alignment = BoxContainer.ALIGNMENT_CENTER
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(face)
	return face


static func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
