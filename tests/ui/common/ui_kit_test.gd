extends GdUnitTestSuite
## The UI kit: icon library, glossary, tooltip, IconStat, SkillCard and
## ActionButton (ui/common/, style guide in ui/README.md).

const REQUIRED_ICONS: Array[String] = [
	"atk", "def", "spd", "battery", "hp", "ela", "energy", "grid_power", "material", "time",
	"defense_level", "pressure", "alert", "losses",
	"trait_aggressive", "trait_defensive", "trait_solitary", "trait_supportive", "trait_reactive", "trait_methodical",
	"action_attack", "action_reinforce", "action_wait", "action_retreat", "action_fast_forward",
	"intent_attack", "intent_guard", "intent_heal", "intent_charge", "intent_buff",
	"status_guard", "status_charging", "status_waiting", "status_low_energy", "status_down", "status_intent_changed",
]


func test_every_required_icon_is_defined() -> void:
	for id in REQUIRED_ICONS:
		assert_bool(UiIcons.has(id)).override_failure_message(id).is_true()


func test_every_icon_has_a_texture_name_color_and_lines() -> void:
	var palette := FeelData.palette()
	for id in UiIcons.ids():
		var entry: Dictionary = UiIcons.table()[id]
		assert_bool(ResourceLoader.exists(str(entry.get("texture", "")))).override_failure_message(id).is_true()
		assert_str(str(entry.get("name", ""))).override_failure_message(id).is_not_empty()
		assert_str(str(entry.get("text", ""))).override_failure_message(id).is_not_empty()
		assert_bool(palette.has(str(entry.get("color", "")))).override_failure_message(id).is_true()


func test_every_icon_is_twelve_pixels_square() -> void:
	for id in UiIcons.ids():
		assert_vector(UiIcons.texture(id).get_size()).override_failure_message(id).is_equal(Vector2(12, 12))


func test_an_unknown_icon_falls_back_to_the_unknown_icon() -> void:
	assert_object(UiIcons.texture("no_such_icon")).is_same(UiIcons.texture("unknown"))
	assert_str(UiIcons.display_name("no_such_icon")).is_equal("Unknown")


func test_every_glossary_keyword_has_lines_and_a_known_icon() -> void:
	for k: String in UiGlossary.keywords():
		var e: Dictionary = UiGlossary.keywords()[k]
		assert_str(str(e.get("text", ""))).override_failure_message(k).is_not_empty()
		if e.has("icon"):
			assert_bool(UiIcons.has(str(e["icon"]))).override_failure_message(k).is_true()


func test_keywords_are_found_as_whole_words_ignoring_case_in_order() -> void:
	var found := UiGlossary.find_keywords("Deal 12. pierce 20%. Guard after. Guarded guard.")
	assert_array(found).is_equal(["Pierce", "Guard"])
	assert_array(UiGlossary.find_keywords("Downtown energyless")).is_empty()


func test_highlight_colors_keywords_and_escapes_brackets() -> void:
	var out := UiGlossary.highlight("[x] Gain Guard.", Color.RED)
	assert_str(out).is_equal("[lb]x] Gain [color=#ff0000]Guard[/color].")


func test_a_tooltip_has_a_name_lines_numbers_and_a_box_per_keyword() -> void:
	var tip: UiTooltip = auto_free(UiTooltip.build("Beam", "Deal 12. Pierce 20%. Then Guard.", "Energy: 3", "energy"))
	assert_str((tip.find_child("Title", true, false) as Label).text).is_equal("Beam")
	assert_str((tip.find_child("Body", true, false) as RichTextLabel).text).contains("Pierce")
	assert_str((tip.find_child("Numbers", true, false) as RichTextLabel).get_parsed_text()).is_equal("Energy: 3")
	assert_object(tip.find_child("Keyword_Pierce", true, false)).is_not_null()
	assert_object(tip.find_child("Keyword_Guard", true, false)).is_not_null()
	assert_object(tip.find_child("Keyword_Energy", true, false)).is_not_null()


func test_attach_stores_the_lines_and_changes_them_in_place() -> void:
	var c: Control = auto_free(Control.new())
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTooltip.attach(c, "A", "first")
	UiTooltip.attach(c, "A", "second", "3")
	assert_str(UiTooltip.spec(c)["body"]).is_equal("second")
	assert_str(UiTooltip.spec(c)["numbers"]).is_equal("3")
	assert_int(c.mouse_entered.get_connections().size()).is_equal(1)
	assert_int(c.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)


func test_icon_stat_shows_the_number_and_tooltips_name_and_value() -> void:
	var s: IconStat = auto_free(IconStat.make("atk", 12))
	assert_str(s.value_text()).is_equal("12")
	s.set_value(14.6)
	assert_str(s.value_text()).is_equal("15")
	var tip := UiTooltip.spec(s)
	assert_str(tip["title"]).is_equal("Attack")
	assert_str(tip["body"]).is_equal(UiIcons.text("atk"))
	assert_str(tip["numbers"]).is_equal("Attack: 15")
	assert_object(s.icon_rect.texture).is_same(UiIcons.texture("atk"))


func test_icon_stat_without_a_value_is_icon_only() -> void:
	var s: IconStat = auto_free(IconStat.make("trait_supportive"))
	assert_bool(s.value_label.visible).is_false()
	assert_str(UiTooltip.spec(s)["numbers"]).is_empty()
	s.set_tip_text("Shields allies first.")
	assert_str(UiTooltip.spec(s)["body"]).is_equal("Shields allies first.")


func test_skill_card_shows_name_cost_rank_and_effect() -> void:
	var card: SkillCard = auto_free(SkillCard.make("Beam", 3, "Deal 12. Pierce 20%.", SkillCard.rank_text(2)))
	assert_str(card.name_label.text).is_equal("Beam")
	assert_str(card.cost_label.text).is_equal("3")
	assert_str(card.rank_label.text).is_equal("+2")
	assert_str(card.effect_label.text).contains("[color=")
	assert_str(card.text).is_empty()
	assert_str(UiTooltip.spec(card)["title"]).is_equal("Beam +2")
	card.set_skill("Mega Beam", 4, "Deal 18.", SkillCard.rank_text(0))
	assert_bool(card.rank_label.visible).is_false()
	assert_str(UiTooltip.spec(card)["title"]).is_equal("Mega Beam")


func test_skill_card_tooltip_says_why_it_cannot_be_played() -> void:
	var card: SkillCard = auto_free(SkillCard.make("Beam", 3, "Deal 12."))
	card.set_problem("Needs 3 Energy.")
	assert_str(UiTooltip.spec(card)["body"]).contains("Needs 3 Energy.")
	card.set_problem("")
	assert_str(UiTooltip.spec(card)["body"]).is_equal("Deal 12.")


func test_action_button_always_shows_its_label_and_cost() -> void:
	var b: ActionButton = auto_free(ActionButton.make("action_reinforce", "Reinforce", "material", 2))
	assert_str(b.label.text).is_equal("Reinforce")
	assert_str(b.cost_stat.value_text()).is_equal("2")
	assert_str(UiTooltip.spec(b)["numbers"]).is_equal("Cost: 2 Material")
	b.set_cost("", null)
	assert_object(b.cost_stat).is_null()
	assert_str(UiTooltip.spec(b)["numbers"]).is_empty()
