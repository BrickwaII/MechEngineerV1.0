extends GdUnitTestSuite
## The design system (ui/README.md): UiStyle, UiFormula and math tooltips,
## StatStrip, Flag, DetailModal, ControlStrip, UiTabs, InfoCard and the style
## check page.


func after_test() -> void:
	DetailModal.close_current()
	UiTooltip.hide_tooltip()


# --- UiStyle ---------------------------------------------------------------

func test_spacing_steps_sit_on_the_grid() -> void:
	assert_int(UiStyle.grid()).is_equal(8)
	assert_int(UiStyle.space("xs")).is_equal(4)
	for step in ["s", "m", "l", "xl"]:
		assert_int(UiStyle.space(step) % UiStyle.grid()).override_failure_message(step).is_equal(0)


func test_every_color_role_names_a_palette_color() -> void:
	var palette := FeelData.palette()
	assert_array(UiStyle.roles()).contains(["text", "interactive", "good", "bad", "caution", "info", "rare", "hint"])
	for r in UiStyle.roles():
		assert_bool(palette.has(UiStyle.role_palette_name(r))).override_failure_message(r).is_true()


func test_only_cards_and_overlays_have_borders() -> void:
	assert_array(UiStyle.PANELS).is_equal(["plain", "card", "overlay"])
	assert_bool(UiStyle.has_border("plain")).is_false()
	assert_int(UiStyle.panel("plain").border_width_top).is_equal(0)
	assert_int(UiStyle.panel("card").border_width_top).is_greater(0)
	assert_int(UiStyle.panel("overlay").border_width_top).is_greater(0)
	assert_object(UiStyle.panel("card", true).border_color).is_not_equal(UiStyle.panel("card").border_color)


func test_the_minimum_text_size_is_the_body_size() -> void:
	assert_int(UiStyle.min_text_size()).is_equal(PixelTheme.font_size("body"))
	assert_int(UiTooltip.text_size()).is_equal(PixelTheme.font_size("body"))


# --- UiFormula and math tooltips ------------------------------------------

func test_a_formula_reads_with_its_real_values() -> void:
	var f := UiFormula.new().term("ATK", 12).op("−").term("DEF", 8).op("×") \
		.open().num(1).op("−").term("Pierce", "20%").close().equals(6)
	assert_str(f.text()).is_equal("ATK 12 − DEF 8 × (1 − Pierce 20%) = 6")


func test_a_template_formula_fills_its_tokens() -> void:
	var f := UiFormula.parse("{ATK} − {DEF} × (1 − {Pierce})", {"ATK": 12, "DEF": 8, "Pierce": "20%"}, 6)
	assert_str(f.text()).is_equal("ATK 12 − DEF 8 × (1 − Pierce 20%) = 6")
	assert_str(UiFormula.parse("{Inclusion} / {Base}", {"Inclusion": "43%", "Base": "0.96%"}, 45, "Lift").text()) \
		.is_equal("Inclusion 43% / Base 0.96% = 45 Lift")
	assert_str(UiFormula.parse("{Missing} + 1", {}).text()).is_equal("Missing ? + 1")
	assert_str(UiFormula.parse("{Wait} / {SPD}", {"Wait": 100, "SPD": 11}, 9.0909, "ticks").text()).is_equal("Wait 100 / SPD 11 = 9.09 ticks")


func test_formula_numbers_drop_needless_decimals() -> void:
	assert_str(UiFormula.fmt(3.0)).is_equal("3")
	assert_str(UiFormula.fmt(1.25)).is_equal("1.25")
	assert_str(UiFormula.percent(0.2)).is_equal("20%")
	assert_str(UiFormula.fmt("?")).is_equal("?")


func test_a_colored_formula_parses_back_to_its_plain_text() -> void:
	var f := UiFormula.parse("{ATK} − {DEF}", {"ATK": 12, "DEF": 8}, 4)
	var r: RichTextLabel = auto_free(RichTextLabel.new())
	r.bbcode_enabled = true
	r.text = f.bbcode()
	assert_str(r.get_parsed_text()).is_equal(f.text())
	assert_str(f.bbcode()).contains("[color=")


func test_a_tooltip_shows_its_math_under_the_numbers() -> void:
	var f := UiFormula.parse("{ATK} − {DEF}", {"ATK": 12, "DEF": 8}, 4)
	var tip: UiTooltip = auto_free(UiTooltip.build("Damage", "Its next hit.", "Damage: 4", "atk", [f, "Before Guard."]))
	var math: RichTextLabel = tip.find_child("Math", true, false)
	assert_object(math).is_not_null()
	assert_str(math.get_parsed_text()).is_equal("ATK 12 − DEF 8 = 4\nBefore Guard.")


func test_set_math_changes_only_the_math_of_an_attached_tooltip() -> void:
	var c: Control = auto_free(Control.new())
	UiTooltip.attach(c, "Damage", "Its next hit.", "4")
	UiTooltip.set_math(c, [UiFormula.parse("{ATK} − {DEF}", {"ATK": 12, "DEF": 8}, 4)])
	var s := UiTooltip.spec(c)
	assert_str(s["body"]).is_equal("Its next hit.")
	assert_int((s["math"] as Array).size()).is_equal(1)


func test_icon_stat_math_reaches_its_tooltip() -> void:
	var stat: IconStat = auto_free(IconStat.make("atk", 4))
	stat.set_math(["ATK 12 − DEF 8 = 4"])
	assert_array(UiTooltip.spec(stat)["math"]).is_equal(["ATK 12 − DEF 8 = 4"])
	stat.set_value(5)
	assert_array(UiTooltip.spec(stat)["math"]).is_equal(["ATK 12 − DEF 8 = 4"])


# --- StatStrip ---------------------------------------------------------------

func test_a_strip_shows_three_headlines_with_their_own_graphics() -> void:
	var s: StatStrip = auto_free(StatStrip.make([
		StatStrip.bar("hp", 38, 50), StatStrip.number("atk", 12), StatStrip.ring("odds", 0.62),
	]))
	assert_array(s.kinds()).is_equal(["bar", "number", "ring"])
	assert_object(s.headline(0).meter).is_not_null()
	assert_str(s.headline(0).text()).is_equal("38/50")
	assert_str(s.headline(1).text()).is_equal("12")
	assert_int(s.headline(1).value_label.get_theme_font_size("font_size")).is_equal(PixelTheme.font_size("title"))
	assert_object(s.headline(2).gauge).is_not_null()
	assert_str(s.headline(2).text()).is_equal("62%")


func test_every_kind_has_its_text() -> void:
	var s: StatStrip = auto_free(StatStrip.make([
		StatStrip.arrow("multiplier", 1.5), StatStrip.pips("defense_level", 2, 5), StatStrip.chip("spd", "2nd"),
	]))
	assert_str(s.headline(0).text()).is_equal("×1.5")
	assert_str(s.headline(1).text()).is_equal("")
	assert_str(UiTooltip.spec(s.headline(1))["numbers"]).is_equal("Defense level: 2/5")
	assert_str(s.headline(2).text()).is_equal("2nd")
	assert_array(StatStrip.KINDS).contains(["bar", "number", "ring", "arrow", "pips", "chip"])


func test_a_bar_headline_animates_in_place_on_a_new_value() -> void:
	var s: StatStrip = auto_free(StatStrip.make([
		StatStrip.bar("hp", 38, 50), StatStrip.number("atk", 12), StatStrip.ring("odds", 0.5),
	]))
	var meter := s.headline(0).meter
	s.set_stat(0, StatStrip.bar("hp", 20, 50))
	assert_object(s.headline(0).meter).is_same(meter)
	assert_float(meter.value).is_equal(20.0)
	assert_str(s.headline(0).value_label.text).is_equal("20/50")


func test_a_headline_tooltip_carries_its_math() -> void:
	var f := UiFormula.parse("{ATK} − {DEF}", {"ATK": 12, "DEF": 8}, 4)
	var s: StatStrip = auto_free(StatStrip.make([
		StatStrip.bar("hp", 1, 2), StatStrip.number("atk", 4, "Next hit.", [f]), StatStrip.ring("odds", 0.5),
	]))
	var spec := UiTooltip.spec(s.headline(1))
	assert_str(spec["body"]).is_equal("Next hit.")
	assert_int((spec["math"] as Array).size()).is_equal(1)


# --- Flag ------------------------------------------------------------------

func test_every_catalog_flag_has_a_label_known_icon_and_role() -> void:
	for id: String in Flag.catalog():
		var e: Dictionary = Flag.catalog()[id]
		assert_str(str(e.get("label", ""))).override_failure_message(id).is_not_empty()
		assert_bool(UiIcons.has(str(e.get("icon", "")))).override_failure_message(id).is_true()
		assert_bool(str(e.get("role", "")) in UiStyle.roles()).override_failure_message(id).is_true()
		assert_str(str(e.get("text", ""))).override_failure_message(id).is_not_empty()


func test_a_flag_is_an_icon_and_word_on_a_tinted_fill_without_a_border() -> void:
	var f: Flag = auto_free(Flag.of("boss"))
	assert_str(f.label.text).is_equal("Boss")
	assert_bool(f.label.visible).is_true()
	assert_object(f.icon_rect).is_not_null()
	var box := f.get_theme_stylebox("panel") as StyleBoxFlat
	assert_int(box.border_width_left).is_equal(0)
	assert_object(box.bg_color).is_equal(Flag.fill_color("rare"))
	assert_str(UiTooltip.spec(f)["title"]).is_equal("Boss")


func test_a_compact_flag_shows_only_its_icon_and_keeps_its_name_on_hover() -> void:
	var f: Flag = auto_free(Flag.of("low_hp", true))
	assert_bool(f.label.visible).is_false()
	assert_str(UiTooltip.spec(f)["title"]).is_equal("Low HP")


func test_an_unknown_flag_is_neutral_and_named_after_its_id() -> void:
	var f: Flag = auto_free(Flag.of("strange_thing"))
	assert_str(f.label.text).is_equal("Strange Thing")
	assert_str(f.color_role).is_equal("neutral")


# --- DetailModal -------------------------------------------------------------

func _spec() -> Dictionary:
	return {"title": "Bolt", "icon": "hp", "flags": [Flag.of("elite")], "sections": [
		{"title": "Stats", "content": DetailModal.rows([["atk", "Attack", 12, ["Base 10 + Rank 2 = 12"]]])},
		{"title": "Skills", "content": DetailModal.prose("Deal 9. Pierce 20%.")},
	]}


func test_the_more_button_opens_the_modal_with_tabs_per_section() -> void:
	var b: Button = auto_free(DetailModal.more_button(_spec))
	add_child(b)
	b.pressed.emit()
	assert_bool(DetailModal.is_open()).is_true()
	var m := DetailModal.current
	assert_str(m.title).is_equal("Bolt")
	assert_array(m.tabs.ids()).is_equal([&"s0", &"s1"])
	assert_bool(m.tabs.bar.visible).is_true()
	assert_object(m.find_child("Flag_elite", true, false)).is_not_null()


func test_esc_closes_the_modal() -> void:
	var m := DetailModal.open(self, _spec())
	var closed := [false]
	m.closed.connect(func() -> void: closed[0] = true)
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	m._input(esc)
	assert_bool(closed[0]).is_true()
	assert_bool(DetailModal.is_open()).is_false()


func test_the_close_button_and_a_click_outside_close_it() -> void:
	var m := DetailModal.open(self, _spec())
	m.close_button.pressed.emit()
	assert_bool(DetailModal.is_open()).is_false()
	m = DetailModal.open(self, _spec())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(m.find_child("Dim", true, false) as Control).gui_input.emit(click)
	assert_bool(DetailModal.is_open()).is_false()


func test_a_right_click_on_an_attached_card_opens_it() -> void:
	var card: Control = auto_free(Control.new())
	add_child(card)
	DetailModal.attach(card, _spec)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	card.gui_input.emit(click)
	assert_bool(DetailModal.is_open()).is_true()


func test_only_one_modal_is_open_at_a_time() -> void:
	var first := DetailModal.open(self, _spec())
	var second := DetailModal.open(self, {"title": "Other"})
	assert_object(DetailModal.current).is_same(second)
	assert_bool(first._layer.is_queued_for_deletion()).is_true()


func test_modal_rows_explain_their_math_on_hover() -> void:
	var g: GridContainer = auto_free(DetailModal.rows([["atk", "Attack", 12, ["Base 10 + Rank 2 = 12"]]]))
	assert_int(g.get_child_count()).is_equal(3)
	assert_array(UiTooltip.spec(g.get_child(2))["math"]).is_equal(["Base 10 + Rank 2 = 12"])


# --- ControlStrip and UiTabs -------------------------------------------------

func test_a_choice_emits_changed_once_per_new_value() -> void:
	var strip: ControlStrip = auto_free(ControlStrip.new())
	strip.add_choice(&"view", "View", [[&"compact", "Compact"], [&"detailed", "Detailed"]], &"compact")
	var seen: Array = []
	strip.changed.connect(func(id: StringName, v: Variant) -> void: seen.append([id, v]))
	strip.press(&"view", &"detailed")
	strip.press(&"view", &"detailed")
	assert_array(seen).is_equal([[&"view", &"detailed"]])
	assert_bool(strip.button(&"view", &"detailed").button_pressed).is_true()
	assert_bool(strip.button(&"view", &"compact").button_pressed).is_false()


func test_set_value_moves_a_choice_quietly() -> void:
	var strip: ControlStrip = auto_free(ControlStrip.new())
	strip.add_choice(&"view", "", [[&"a", "A"], [&"b", "B"]], &"a")
	var seen: Array = []
	strip.changed.connect(func(id: StringName, v: Variant) -> void: seen.append(v))
	strip.set_value(&"view", &"b")
	assert_array(seen).is_empty()
	assert_str(str(strip.value(&"view"))).is_equal("b")
	assert_bool(strip.button(&"view", &"b").button_pressed).is_true()


func test_a_toggle_flips_and_reports() -> void:
	var strip: ControlStrip = auto_free(ControlStrip.new())
	strip.add_toggle(&"log", "Log", false, "status_waiting")
	var seen: Array = []
	strip.changed.connect(func(id: StringName, v: Variant) -> void: seen.append(v))
	strip.press(&"log")
	assert_array(seen).is_equal([true])
	assert_bool(strip.value(&"log")).is_true()
	assert_object(strip.button(&"log").icon).is_not_null()


func test_tabs_show_one_page_at_a_time() -> void:
	var tabs: UiTabs = auto_free(UiTabs.new())
	var a: Control = Control.new()
	var b: Control = Control.new()
	tabs.add_tab(&"a", "A", a)
	assert_bool(tabs.bar.visible).is_false()
	tabs.add_tab(&"b", "B", b)
	assert_bool(tabs.bar.visible).is_true()
	assert_bool(a.visible).is_true()
	tabs.select(&"b")
	assert_bool(a.visible).is_false()
	assert_bool(b.visible).is_true()
	assert_bool(tabs.button(&"b").button_pressed).is_true()


# --- InfoCard ----------------------------------------------------------------

func test_nothing_is_drawn_over_a_card_portrait() -> void:
	for layout in ["vertical", "horizontal"]:
		var art: Control = Control.new()
		var card: InfoCard = auto_free(InfoCard.make("Bolt", art, [
			StatStrip.bar("hp", 1, 2), StatStrip.number("atk", 3), StatStrip.chip("spd", "1st"),
		], [Flag.of("elite")], _spec, layout))
		assert_int(art.get_child_count()).override_failure_message(layout).is_equal(0)
		assert_bool(art.is_ancestor_of(card.strip)).is_false()
		assert_bool(art.is_ancestor_of(card.flags_row)).is_false()
		assert_object(card.more).is_not_null()
		assert_bool(card.title_row.is_ancestor_of(card.more)).is_true()


func test_a_card_without_details_has_no_more_button() -> void:
	var card: InfoCard = auto_free(InfoCard.make("Bolt", Control.new(), [
		StatStrip.bar("hp", 1, 2), StatStrip.number("atk", 3), StatStrip.chip("spd", "1st"),
	]))
	assert_object(card.more).is_null()
	assert_bool(card.flags_row.visible).is_false()


func test_a_card_opens_its_detail() -> void:
	var card: InfoCard = auto_free(InfoCard.make("Bolt", Control.new(), [
		StatStrip.bar("hp", 1, 2), StatStrip.number("atk", 3), StatStrip.chip("spd", "1st"),
	], [], _spec))
	add_child(card)
	card.more.pressed.emit()
	assert_str(DetailModal.current.title).is_equal("Bolt")


# --- The style check page -----------------------------------------------------

func _page() -> Control:
	var page: Control = auto_free(load("res://ui/common/demo/style_check.tscn").instantiate())
	add_child(page)
	return page


func _walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		_walk(c, out)
	return out


func test_the_style_check_page_has_exactly_one_control_strip() -> void:
	var count := 0
	for n in _walk(_page(), []):
		if n is ControlStrip:
			count += 1
	assert_int(count).is_equal(1)


func test_small_text_on_the_style_check_page_is_only_captions() -> void:
	for n in _walk(_page(), []):
		if n is Label and (n as Label).is_visible_in_tree():
			var l := n as Label
			if l.get_theme_font_size("font_size") < UiStyle.min_text_size():
				assert_bool(UiStyle.is_caption(l)).override_failure_message("small text: %s" % l.text).is_true()


func test_gaps_on_the_style_check_page_sit_on_the_grid() -> void:
	var allowed := UiStyle.spaces()
	for n in _walk(_page(), []):
		if n is BoxContainer and (n as Control).has_theme_constant_override("separation"):
			var sep := (n as Control).get_theme_constant("separation")
			assert_bool(sep in allowed).override_failure_message("%s gap %d" % [n.get_path(), sep]).is_true()
		if n is HFlowContainer or n is GridContainer:
			for k in ["h_separation", "v_separation"]:
				if (n as Control).has_theme_constant_override(k):
					var sep := (n as Control).get_theme_constant(k)
					assert_bool(sep in allowed).override_failure_message("%s %s %d" % [n.get_path(), k, sep]).is_true()
