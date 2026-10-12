extends Control
## The UI kit on one screen: icon library, IconStats, SkillCards and
## ActionButtons. Hover anything for its tooltip.

var first_card: SkillCard


func _ready() -> void:
	theme = PixelTheme.theme()
	var bg := ColorRect.new()
	bg.color = FeelData.color("background")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.position = Vector2(24, 20)
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	_title(col, "ICONS")
	var grid := GridContainer.new()
	grid.columns = 13
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for id in UiIcons.ids():
		grid.add_child(IconStat.make(id))

	_title(col, "UNIT")
	var unit := HBoxContainer.new()
	unit.add_theme_constant_override("separation", 14)
	col.add_child(unit)
	for pair in [["hp", "38/50"], ["energy", 6], ["atk", 12], ["def", 8], ["spd", 11], ["battery", 10], ["ela", 3]]:
		unit.add_child(IconStat.make(pair[0], pair[1]))
	unit.add_child(VSeparator.new())
	for id in ["trait_aggressive", "trait_methodical"]:
		unit.add_child(IconStat.make(id))

	_title(col, "RUN")
	var run := HBoxContainer.new()
	run.add_theme_constant_override("separation", 14)
	col.add_child(run)
	for pair in [["time", 9], ["map_energy", 24], ["material", 15], ["grid_power", 4], ["pressure", 3], ["alert", 2], ["losses", 2], ["defense_level", 2]]:
		run.add_child(IconStat.make(pair[0], pair[1]))

	_title(col, "SKILLS")
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	col.add_child(cards)
	first_card = SkillCard.make("Beam", 3, "Deal 12. Pierce 20%.", SkillCard.rank_text(2))
	cards.add_child(first_card)
	cards.add_child(SkillCard.make("Mega Overcharge Shot", 4, "Deal 18 to one enemy."))
	cards.add_child(SkillCard.make("Brace", 2, "Gain Guard 40%."))
	var off := SkillCard.make("Arc Sweep", 6, "Deal 7 to all enemies.")
	off.disabled = true
	off.set_problem("Needs 6 Energy.")
	cards.add_child(off)

	_title(col, "MAP ACTIONS")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	col.add_child(actions)
	actions.add_child(ActionButton.make("action_attack", "Attack", "time", 1))
	actions.add_child(ActionButton.make("action_reinforce", "Reinforce", "material", 2))
	actions.add_child(ActionButton.make("action_wait", "Wait", "time", 1))
	actions.add_child(ActionButton.make("action_retreat", "Retreat"))
	actions.add_child(ActionButton.make("action_fast_forward", "Fast-forward"))


func _title(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"SmallLabel"
	parent.add_child(l)
