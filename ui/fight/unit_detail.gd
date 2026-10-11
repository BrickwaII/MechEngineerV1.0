extends RefCounted
## The full readout of one unit, shown when the pointer rests on its card: all
## its stats, its skills with level, energy cost and what they do, its
## statuses, and for an enemy what it means to do next and why it changed.
## text() is the same content as plain lines, for tests and the tooltip text.
## Sizes and colors: data/feel/battle_readout.json "detail".


## The unit's readout as lines. `statuses` is the status row's words
## ("GUARD 40% · LOW EN"), `intent` the enemy's intent in words, `change` its
## "changed: <why>", `tag` its personality tag; each may be "".
static func lines(unit: Combatant, statuses := "", intent := "", change := "", tag := "") -> PackedStringArray:
	var out := PackedStringArray()
	var side := "ENEMY" if unit.side == Combatant.Side.ENEMY else "SQUAD"
	out.append("%s  (%s%s)" % [unit.display_name.to_upper(), side, ", " + tag if not tag.is_empty() else ""])
	@warning_ignore("integer_division")
	var max_energy := unit.max_energy_milli / Combatant.MILLI
	out.append("HP %d/%d   EN %d/%d" % [unit.hp, unit.max_hp, unit.energy(), max_energy])
	var s := unit.stats
	out.append("ATK %d   DEF %d   SPD %d" % [s.attack, s.defense, s.speed])
	out.append("BAT %d   ELA %d" % [s.battery_capacity, s.elasticity])
	out.append("SKILLS")
	for skill in unit.skills():
		out.append("  %s" % skill_line(skill))
	out.append("STATUS")
	out.append("  %s" % (statuses if not statuses.is_empty() else "none"))
	if not intent.is_empty():
		out.append("NEXT")
		out.append("  %s" % intent)
	if not change.is_empty():
		out.append("  %s" % change)
	return out


## "Overcharge Shot Lv2  4 EN  dmg 165%, one enemy".
static func skill_line(skill: CombatSkill) -> String:
	var level := " Lv%d" % skill.level
	var what := ""
	if skill.is_heal():
		what = "heal %d%%" % skill.power_percent
	elif skill.is_guard():
		what = "guard %d%%" % skill.power_percent
	else:
		what = "dmg %d%%" % skill.power_percent
	var aim: String = "all enemies" if skill.hits_all() else {
		CombatSkill.TARGET_SELF: "self", CombatSkill.TARGET_ALLY: "one ally"}.get(skill.target, "one enemy")
	return "%s%s  %d EN  %s, %s" % [skill.display_name, level, skill.energy_cost, what, aim]


## The readout as a card, for the tooltip.
static func card(unit: Combatant, statuses := "", intent := "", change := "", tag := "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme = PixelTheme.theme()
	var style := StyleBoxFlat.new()
	style.bg_color = FeelData.color("panel")
	style.border_color = ReadoutStyle.color("detail.border")
	style.set_border_width_all(2)
	style.set_content_margin_all(8)
	style.anti_aliasing = false
	panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2(ReadoutStyle.number("detail.width_px", 300), 0)
	panel.add_child(col)
	for line in lines(unit, statuses, intent, change, tag):
		var label := Label.new()
		label.text = line
		label.theme_type_variation = &"SmallLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var heading := line in ["SKILLS", "STATUS", "NEXT"]
		var first := col.get_child_count() == 0
		label.add_theme_color_override("font_color", ReadoutStyle.color(
			"detail.title" if first else ("detail.heading" if heading else "stats.text")))
		col.add_child(label)
	return panel
