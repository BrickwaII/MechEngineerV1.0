class_name DraftScreen
extends Control
## Squad draft: shows the seeded draft as cards, lets the player pick
## squad_size bots by clicking them, and emits squad_chosen on START FIGHT.
## Draft and squad sizes come from data/bot_data/ through BotTuning.
##
## Presentation (data/feel/screens.json "draft"): the cards flip in one after
## another, lift under the cursor, and a picked bot's sprite snaps down into
## its slot in the squad bar; dropping it empties the slot.

const Palette := preload("res://ui/fight/fight_palette.gd")

signal squad_chosen(squad: Array[SquadMemberSummary])

const SLOT_SIZE := Vector2(96, 84)

## Set before the screen enters the tree.
var draft_seed := 0
var bot_tuning: BotTuning
## The fight's combat tuning with the run's fight variants; cards show skill
## costs and numbers from it. Null uses the default tuning.
var combat_tuning: CombatTuning
var settings: GameSettings
var picker: DraftPicker

var cards: Dictionary[String, Button] = {}
var start_button: Button
var count_label: Label
## The squad bar's slots, in pick order.
var slots: Array[Panel] = []

## Bot id -> the sprite shown in its slot.
var _slot_sprites := {}
## Sprites on their way from a card to a slot.
var _flyers: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = ScreenTheme.theme()
	if bot_tuning == null:
		bot_tuning = BotTuning.load_default()
	picker = DraftPicker.new(bot_tuning, draft_seed)
	_build_layout()
	refresh()
	_flip_in.call_deferred()


func toggle(bot_id: String) -> String:
	var was_picked := picker.is_picked(bot_id)
	var problem := picker.toggle(bot_id)
	if not problem.is_empty():
		SoundPlayer.fire(&"ui_error")
	elif was_picked:
		SoundPlayer.fire(&"ui_back")
	refresh()
	if problem.is_empty() and not was_picked:
		_snap_into_squad(bot_id)
	return problem


func start() -> void:
	if picker.can_start():
		SoundPlayer.fire(&"ui_confirm")
		squad_chosen.emit(picker.summaries())


func refresh() -> void:
	var picked := picker.picked_ids()
	for bot_id in cards:
		cards[bot_id].button_pressed = picker.is_picked(bot_id)
		(cards[bot_id] as DraftCard).set_pick_order(picked.find(bot_id) + 1)
	count_label.text = "%d / %d picked" % [picked.size(), picker.squad_size()]
	start_button.disabled = not picker.can_start()
	_refresh_slots()


## The bot in each squad slot, "" for an empty one.
func slot_bot_ids() -> Array[String]:
	var out: Array[String] = []
	var picked := picker.picked_ids()
	for i in slots.size():
		out.append(picked[i] if i < picked.size() else "")
	return out


func _flip_in() -> void:
	var stagger := ScreenFeel.seconds("draft.flip_stagger_ms", _s())
	var i := 0
	for bot in picker.bots():
		(cards[bot.id] as DraftCard).flip_in(stagger * i)
		i += 1


## Puts each picked bot's sprite in its slot; a slot whose bot changed is
## rebuilt, so dropping a bot slides the later picks along.
func _refresh_slots() -> void:
	var ids := slot_bot_ids()
	for i in slots.size():
		var slot := slots[i]
		var current: String = slot.get_meta("bot_id", "")
		if current == ids[i]:
			continue
		for child in slot.get_children():
			if child is UnitSprite:
				child.queue_free()
		_slot_sprites.erase(current)
		slot.set_meta("bot_id", ids[i])
		if ids[i].is_empty():
			continue
		var sprite := _sprite_for(ids[i])
		sprite.position = SLOT_SIZE / 2.0
		slot.add_child(sprite)
		_slot_sprites[ids[i]] = sprite


## A copy of the card's sprite flies from the card into its slot, and the
## slot's sprite pops as it lands.
func _snap_into_squad(bot_id: String) -> void:
	var index := picker.picked_ids().find(bot_id)
	if index < 0 or index >= slots.size() or not _slot_sprites.has(bot_id):
		return
	var landed: UnitSprite = _slot_sprites[bot_id]
	var snap := ScreenFeel.seconds("draft.snap_ms", _s())
	if snap <= 0.0:
		SoundPlayer.fire(&"card_snap")
		return
	landed.visible = false
	var flyer := _sprite_for(bot_id)
	var card := cards[bot_id] as DraftCard
	flyer.scale = card.sprite.scale
	flyer.position = card.sprite_global_position() - _flyers.global_position
	_flyers.add_child(flyer)
	var end := slots[index].global_position + SLOT_SIZE / 2.0 - _flyers.global_position
	var rest := landed.scale
	var tween := create_tween()
	tween.tween_property(flyer, "position", end, snap).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(flyer, "scale", rest, snap).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		flyer.queue_free()
		if is_instance_valid(landed):
			landed.visible = true
			landed.scale = rest * ScreenFeel.number("draft.snap_pop_scale", 1.0)
			FeelTween.to(landed, "scale", rest, "ui_pop", _s())
		SoundPlayer.fire(&"card_snap"))


func _sprite_for(bot_id: String) -> UnitSprite:
	var sprite := UnitSprite.new()
	sprite.settings = settings
	sprite.setup(DraftCard.ALLY_UNIT, str(ScreenFeel.value("draft.sprite_tier", "beginner")),
		SpriteManifest.ally_look(DraftCard.ALLY_UNIT, DraftCard.look_seed(bot_id)))
	sprite.scale = Vector2.ONE * 2.0
	return sprite


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
	_label(root, "DRAFT YOUR SQUAD", 30, Palette.TEXT_BRIGHT)
	_label(root, "Pick %d of these %d bots, then start the fight. Click a card to pick or drop it." % [
		picker.squad_size(), picker.bots().size()], 10, Palette.TEXT_DIM)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	for bot in picker.bots():
		var card := DraftCard.new(bot, settings, combat_tuning)
		card.pressed.connect(toggle.bind(bot.id))
		row.add_child(card)
		cards[bot.id] = card

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)
	var squad := HBoxContainer.new()
	squad.name = "SquadBar"
	squad.add_theme_constant_override("separation", 8)
	footer.add_child(squad)
	_label(squad, "SQUAD", 10, Palette.TEXT_DIM).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in picker.squad_size():
		var slot := Panel.new()
		slot.name = "Slot%d" % (i + 1)
		slot.custom_minimum_size = SLOT_SIZE
		slot.clip_contents = true
		var style := StyleBoxFlat.new()
		style.bg_color = Palette.PANEL
		style.border_color = Palette.RULE
		style.set_border_width_all(2)
		slot.add_theme_stylebox_override("panel", style)
		squad.add_child(slot)
		slots.append(slot)
	count_label = _label(footer, "", 20, Palette.TEXT)
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "START FIGHT"
	start_button.custom_minimum_size = Vector2(220, 48)
	start_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start_button.pressed.connect(start)
	footer.add_child(start_button)

	_flyers = Control.new()
	_flyers.name = "Flyers"
	_flyers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flyers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flyers)


func _s() -> GameSettings:
	return settings if settings else GameSettings.shared()


static func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", ScreenTheme.size(font_size))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
