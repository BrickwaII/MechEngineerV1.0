extends Control
## The style check: every design-system piece on one screen, to compare
## screens against (ui/README.md). Its own control strip sits on top, as on
## every screen. Hover anything for its tooltip; ⋮ or right-click a card
## opens its detail modal.

var strip: ControlStrip
var damage_badge: StatStrip.Headline
var unit_card: InfoCard
var region_card: InfoCard
var _cards: HFlowContainer
var _layout := "vertical"
var _portrait_size := 96.0


func _ready() -> void:
	theme = PixelTheme.theme()
	var bg := ColorRect.new()
	bg.color = FeelData.color("background")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var page := UiStyle.column("m")
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.offset_left = UiStyle.space("l")
	page.offset_right = -UiStyle.space("l")
	page.offset_top = UiStyle.space("s")
	add_child(page)

	strip = ControlStrip.new()
	strip.add_choice(&"layout", "Cards", [[&"vertical", "Tall"], [&"horizontal", "Wide"]], &"vertical")
	strip.add_choice(&"size", "Size", [[&"s", "S"], [&"m", "M"], [&"l", "L"]], &"m")
	strip.add_toggle(&"log", "Log", false, "status_waiting", "Shows the log drawer.")
	strip.add_spring()
	strip.add_control(&"home", ActionButton.make("action_home", "Home"))
	strip.changed.connect(_on_strip)
	page.add_child(strip)

	var cols := UiStyle.row("xl")
	page.add_child(cols)
	var left := UiStyle.column("m")
	left.custom_minimum_size.x = 440
	cols.add_child(left)
	var right := UiStyle.column("m")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	_section(left, "COLOR ROLES", _roles())
	_section(left, "PANELS: PLAIN INFO / CARD YOU CLICK / OVERLAY", _panels())
	_section(left, "TEXT", _text())
	_section(left, "SPACING (8 PX GRID)", _spacing())

	_section(right, "STAT STRIPS: THREE HEADLINES, SIX GRAPHICS", _strips())
	_section(right, "FLAGS", _flags())
	_cards = HFlowContainer.new()
	_cards.add_theme_constant_override("h_separation", UiStyle.space("m"))
	_cards.add_theme_constant_override("v_separation", UiStyle.space("m"))
	_build_cards("vertical")
	_section(right, "CARD ANATOMY: ART, FLAGS ON THE EDGE, STRIP, ⋮", _cards)


func _section(parent: Node, caption: String, body: Control) -> void:
	var col := UiStyle.column("xs")
	var l := UiStyle.caption(Label.new())
	l.text = caption
	col.add_child(l)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	parent.add_child(col)


func _roles() -> Control:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", UiStyle.space("s"))
	g.add_theme_constant_override("v_separation", UiStyle.space("xs"))
	for r in UiStyle.roles():
		var row := UiStyle.row("xs")
		var sw := ColorRect.new()
		sw.color = UiStyle.role(r)
		sw.custom_minimum_size = Vector2(16, 16)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sw)
		row.add_child(UiStyle.label(r, r if r != "neutral" else "text_quiet"))
		g.add_child(row)
	return g


func _panels() -> Control:
	var row := UiStyle.row("s")
	for kind in UiStyle.PANELS:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiStyle.panel(kind))
		p.custom_minimum_size = Vector2(136, 48)
		p.add_child(UiStyle.label({"plain": "Info", "card": "Click me", "overlay": "Modal"}[kind], "text"))
		row.add_child(p)
	return row


func _text() -> Control:
	var col := UiStyle.column("xs")
	col.add_child(UiStyle.label("Title 30: names", "title", "title"))
	col.add_child(UiStyle.label("Body 20: everything you read", "text"))
	col.add_child(UiStyle.label("Quiet 20: a label for a value", "text_quiet"))
	var cap := UiStyle.caption(Label.new())
	cap.text = "CAPTION 10: ONLY OVER A GROUP"
	col.add_child(cap)
	return col


func _spacing() -> Control:
	var row := UiStyle.row("s")
	for step in ["xs", "s", "m", "l", "xl"]:
		var c := UiStyle.column("xs")
		var bar := ColorRect.new()
		bar.color = UiStyle.role("interactive")
		bar.custom_minimum_size = Vector2(UiStyle.space(step), 16)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		c.add_child(bar)
		c.add_child(UiStyle.label("%s %d" % [step, UiStyle.space(step)], "text_quiet"))
		row.add_child(c)
	return row


func _strips() -> Control:
	var col := UiStyle.column("s")
	var damage := UiFormula.parse("{ATK} − {DEF} × (1 − {Pierce})", {"ATK": 12, "DEF": 8, "Pierce": "20%"}, 6)
	var a := StatStrip.make([
		StatStrip.bar("hp", 38, 50),
		StatStrip.number("atk", 6, "Damage of its next hit on Bolt.", [damage]),
		StatStrip.ring("odds", 0.62, "Won 20 of 32 simulated fights.", ["Won 20 of 32 simulated fights = 62%"]),
	])
	damage_badge = a.headline(1)
	col.add_child(a)
	col.add_child(StatStrip.make([
		StatStrip.arrow("multiplier", 1.5, "Pressure grows this much faster here.",
			[UiFormula.parse("{Base} × {Alert}", {"Base": 1, "Alert": 1.5}, 1.5)]),
		StatStrip.pips("defense_level", 2, 5),
		StatStrip.chip("spd", "2nd", "Acts second: Speed 11 is the second highest.",
			[UiFormula.parse("{Wait} / {SPD}", {"Wait": 100, "SPD": 11}, 9.09, "ticks")]),
	]))
	return col


func _flags() -> Control:
	var flags: Array = []
	for id: String in Flag.catalog():
		flags.append(Flag.of(id))
	for id in ["boss", "low_hp", "fortified"]:
		flags.append(Flag.of(id, true))
	var r := Flag.row(flags)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func _build_cards(layout: String) -> void:
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	unit_card = InfoCard.make("Precinct Overseer", _portrait("rival_walker"), [
		StatStrip.bar("hp", 14, 60),
		StatStrip.number("atk", 11),
		StatStrip.chip("spd", "1st", "Acts next."),
	], [Flag.of("boss"), Flag.of("low_hp")], _unit_detail, layout)
	_cards.add_child(unit_card)
	region_card = InfoCard.make("Harbor District", _portrait("enemy_drone"), [
		StatStrip.ring("odds", 0.78, "Won 25 of 32 simulated fights."),
		StatStrip.pips("defense_level", 3, 5),
		StatStrip.number("material", "+2", "Material each day while held."),
	], [Flag.of("fortified"), Flag.of("new")], _region_detail, layout)
	_cards.add_child(region_card)


func _portrait(unit: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(_portrait_size, _portrait_size)
	var s := UnitSprite.new()
	s.setup(unit, "medium")
	s.scale = Vector2.ONE * _portrait_size / 96.0
	s.position = Vector2(_portrait_size, _portrait_size) / 2.0
	c.add_child(s)
	s.play("idle")
	return c


func _unit_detail() -> Dictionary:
	var stats := DetailModal.rows([
		["hp", "HP", "14/60"], ["atk", "Attack", 11, [UiFormula.parse("{Base} + {Tier}", {"Base": 8, "Tier": 3}, 11)]],
		["def", "Defense", 6], ["spd", "Speed", 9], ["battery", "Battery", 12], ["ela", "Elasticity", 2],
	])
	var skills := UiStyle.row("s")
	skills.add_child(SkillCard.make("Crush", 2, "Deal 11. Pierce 20%.", "+2"))
	skills.add_child(SkillCard.make("Brace", 1, "Gain Guard 40%."))
	var next := DetailModal.prose("Next: Crush on Bolt for 6. Charges when below half HP.")
	return {"title": "Precinct Overseer", "icon": "demo_boss", "flags": [Flag.of("boss"), Flag.of("low_hp")],
		"subtitle": "The act 1 boss.",
		"sections": [
			{"title": "Stats", "content": stats},
			{"title": "Skills", "content": skills},
			{"title": "Next move", "content": next},
		]}


func _region_detail() -> Dictionary:
	return {"title": "Harbor District", "icon": "defense_level", "flags": [Flag.of("fortified")],
		"sections": [{"title": "Region", "content": DetailModal.rows([
			["odds", "Odds", "78%", ["Won 25 of 32 simulated fights"]],
			["defense_level", "Defense", 3], ["pressure", "Pressure", 12], ["material", "Material", "+2"],
		])}]}


func _on_strip(id: StringName, value: Variant) -> void:
	match id:
		&"layout":
			_layout = str(value)
		&"size":
			_portrait_size = {&"s": 64.0, &"m": 96.0, &"l": 128.0}[value]
	_build_cards(_layout)
