extends RefCounted
## The full readout of one unit, shown when the pointer rests on its card: all
## its stats, its skills with level, energy cost and what they do, its
## statuses, and for an enemy what it means to do next and why it changed.
## text() is the same content as plain lines, for tests and the tooltip text.
## Sizes and colors: data/feel/battle_readout.json "detail". spec() is the
## same content as the unit's DetailModal (⋮ on its card).

const StatusRow := preload("res://ui/fight/status_row.gd")


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
		var heading := line in ["SKILLS", "STATUS", "NEXT"]
		var first := col.get_child_count() == 0
		var color := ReadoutStyle.color("detail.title" if first else ("detail.heading" if heading else "stats.text"))
		# Keywords (Guard, Charge, traits) are highlighted, as in every description.
		col.add_child(UiGlossary.rich(line, PixelTheme.font_size("body"), color))
	return panel


## The unit's DetailModal spec (ui/README.md rule 8): every stat, the skills
## with ranks, statuses, the personality and, for an enemy, the next move.
## `opts`: statuses (words), intent, change, tag, boss, elite, turn
## (BattleMath.turn()), personality (ends, may be empty), status_flags
## (status id -> word).
static func spec(unit: Combatant, opts: Dictionary) -> Dictionary:
	var flags: Array = []
	if opts.get("boss", false):
		flags.append(Flag.of("boss"))
	elif opts.get("elite", false):
		flags.append(Flag.of("elite"))
	if not unit.is_alive():
		flags.append(Flag.of("down"))
	var tag := str(opts.get("tag", ""))
	if not tag.is_empty():
		var trait_id := "trait_%s" % tag.to_lower()
		flags.append(Flag.make(tag.capitalize(), trait_id if UiIcons.has(trait_id) else "", "neutral",
			UiIcons.text(trait_id) if UiIcons.has(trait_id) else "Its personality."))
	var sections: Array = [
		{"id": "stats", "title": "Stats", "content": stats_page(unit, opts.get("turn", {}))},
		{"id": "skills", "title": "Skills", "content": skills_page(unit)},
		{"id": "status", "title": "Status", "content": status_page(opts.get("status_flags", {}))},
	]
	var ends: Array[float] = []
	ends.assign(opts.get("personality", []))
	if not ends.is_empty() or not tag.is_empty():
		sections.append({"id": "personality", "title": "Personality", "content": personality_page(ends, tag)})
	var intent := str(opts.get("intent", ""))
	if unit.side == Combatant.Side.ENEMY and not intent.is_empty():
		sections.append({"id": "next", "title": "Next move", "content": next_page(intent, str(opts.get("change", "")))})
	return {"title": unit.display_name, "icon": "demo_boss" if opts.get("boss", false) else ("hp" if unit.side == Combatant.Side.PLAYER else "intent_attack"),
		"subtitle": "%s · %s" % ["Enemy" if unit.side == Combatant.Side.ENEMY else "Squad", str(opts.get("turn", {}).get("tip", ""))],
		"flags": flags, "sections": sections}


static func stats_page(unit: Combatant, turn: Dictionary) -> Control:
	var s := unit.stats
	@warning_ignore("integer_division")
	var max_energy := unit.max_energy_milli / Combatant.MILLI
	var def := str(s.defense) if unit.guard_percent <= 0 else "%d + Guard %d%%" % [s.defense, unit.guard_percent]
	return DetailModal.rows([
		["hp", "HP", "%d/%d" % [unit.hp, unit.max_hp]],
		["energy", "Energy", "%d/%d" % [unit.energy(), max_energy]],
		["atk", "Attack", s.attack],
		["def", "Defense", def],
		["spd", "Speed", s.speed, turn.get("math", [])],
		["battery", "Battery", s.battery_capacity],
		["ela", "Elasticity", s.elasticity],
	])


static func skills_page(unit: Combatant) -> Control:
	var flow := HFlowContainer.new()
	flow.name = "Skills"
	flow.add_theme_constant_override("h_separation", UiStyle.space("s"))
	flow.add_theme_constant_override("v_separation", UiStyle.space("s"))
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for skill in unit.skills():
		var face := BattleScreen.skill_card_face(skill, unit.stats.attack)
		var card := SkillCard.make(face["name"], skill.energy_cost, face["effect"], face["rank"])
		card.name = "Skill_%s" % skill.id
		card.toggle_mode = false
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		flow.add_child(card)
	return flow


static func status_page(status_flags: Dictionary) -> Control:
	var col := UiStyle.column("s")
	col.name = "Status"
	if status_flags.is_empty():
		col.add_child(UiStyle.label("No statuses.", "text_quiet"))
		return col
	for id: String in status_flags:
		var row := UiStyle.row("s")
		var number := StatusRow.number_of(str(status_flags[id]))
		var label := UiIcons.display_name("status_" + id) + ("" if number.is_empty() else " " + number)
		row.add_child(Flag.make(label, "status_" + id, StatusRow.ROLES.get(id, "neutral"), UiIcons.text("status_" + id)))
		var text := DetailModal.prose(UiIcons.text("status_" + id))
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(text)
		col.add_child(row)
	return col


static func personality_page(ends: Array[float], tag: String) -> Control:
	var row := UiStyle.row("m")
	row.name = "Personality"
	if not ends.is_empty():
		var hex := PersonalityHexagon.new()
		hex.name = "Hexagon"
		hex.custom_minimum_size = Vector2(220, 172)
		hex.font_size = PixelTheme.font_size("body")
		hex.show_ends(ends)
		row.add_child(hex)
	var trait_id := "trait_%s" % tag.to_lower()
	var line := "Leans %s: %s" % [tag.capitalize(), UiIcons.text(trait_id)] if UiIcons.has(trait_id) else \
		("Leans %s." % tag.capitalize() if not tag.is_empty() else "No lean yet.")
	var text := DetailModal.prose(line)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	return row


static func next_page(intent: String, change: String) -> Control:
	var col := UiStyle.column("s")
	col.name = "Next"
	col.add_child(DetailModal.prose(intent))
	if not change.is_empty():
		var c := DetailModal.prose(change)
		c.add_theme_color_override("default_color", UiStyle.role("rare"))
		col.add_child(c)
	return col
