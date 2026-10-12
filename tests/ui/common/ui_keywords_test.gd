extends GdUnitTestSuite
## Keyword links (UiGlossary, KeywordPopup): highlighted keywords are links;
## hover shows a keyword's box, click pins it until a click elsewhere or Esc.


func before_test() -> void:
	KeywordPopup.dismiss()


func test_aliases_and_case_map_to_the_keyword() -> void:
	for word in ["Pierce", "piercing", "PIERCES"]:
		assert_str(UiGlossary.keyword(word)).override_failure_message(word).is_equal("Pierce")
	assert_str(UiGlossary.keyword("Fortified")).is_equal("Fortify")
	assert_str(UiGlossary.keyword("National Emergency")).is_equal("Major Crisis")
	assert_str(UiGlossary.keyword("pierced armor")).is_empty()


func test_every_form_names_one_keyword_with_lines() -> void:
	var seen := {}
	for k: String in UiGlossary.keywords():
		var e: Dictionary = UiGlossary.keywords()[k]
		assert_str(str(e.get("text", ""))).override_failure_message(k).is_not_empty()
		if e.has("icon"):
			assert_bool(UiIcons.has(str(e["icon"]))).override_failure_message(k).is_true()
		for form in [k] + Array(e.get("aliases", [])):
			var f := str(form).to_lower()
			assert_bool(seen.has(f)).override_failure_message("%s is used twice" % form).is_false()
			seen[f] = k


func test_highlight_links_each_keyword_to_its_box() -> void:
	var out := UiGlossary.highlight("Piercing shot. Low Energy.", Color.RED)
	assert_str(out).contains("[url=kw:Pierce][hint=][color=#ff0000]Piercing[/color][/hint][/url]")
	# The longer keyword wins over the one inside it.
	assert_str(out).contains("[url=kw:Low Energy]")
	assert_str(out).not_contains("[url=kw:Energy]")
	assert_array(UiGlossary.find_keywords("Piercing, then Guarded.")).is_equal(["Pierce", "Guard"])


func test_links_have_a_dotted_underline_and_no_tooltip_of_their_own() -> void:
	var r: RichTextLabel = auto_free(UiGlossary.rich("Gain Guard 40%.", 10))
	assert_bool(r.hint_underlined).is_true()
	assert_bool(r.meta_underlined).is_false()
	assert_str(r.text).contains("[hint=]")
	assert_str(r.get_tooltip(Vector2.ZERO)).is_empty()


func test_hovered_and_pinned_keywords_take_the_active_look() -> void:
	var active := UiGlossary.highlight("Pierce and Guard", Color.RED, ["Guard"])
	assert_str(active).contains("[url=kw:Guard][hint=][bgcolor=")
	assert_str(active).contains("[url=kw:Pierce][hint=][color=#ff0000]Pierce")
	var r: RichTextLabel = auto_free(UiGlossary.rich("Pierce and Guard", 10))
	add_child(r)
	KeywordPopup.hover("kw:Guard", r)
	assert_str(r.text).contains("[url=kw:Guard][hint=][bgcolor=")
	KeywordPopup.click("kw:Guard", r)
	KeywordPopup.unhover("kw:Guard", r)
	# Pinned: still active after the pointer leaves.
	assert_str(r.text).contains("[url=kw:Guard][hint=][bgcolor=")
	KeywordPopup.dismiss()
	assert_str(r.text).not_contains("[bgcolor=")
	assert_str(r.get_parsed_text()).is_equal("Pierce and Guard")


func test_link_meta_names_the_keyword() -> void:
	assert_str(UiGlossary.link_keyword("kw:Pierce")).is_equal("Pierce")
	assert_str(UiGlossary.link_keyword("https://example.com")).is_empty()
	assert_str(UiGlossary.link_keyword("kw:nothing")).is_empty()


func test_a_rich_label_is_wired_and_passes_clicks_on() -> void:
	var r: RichTextLabel = auto_free(UiGlossary.rich("Gain Guard 40%.", 10))
	assert_int(r.meta_hover_started.get_connections().size()).is_equal(1)
	assert_int(r.meta_clicked.get_connections().size()).is_equal(1)
	assert_int(r.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	assert_str(r.get_parsed_text()).is_equal("Gain Guard 40%.")


func test_hover_shows_and_click_pins() -> void:
	KeywordPopup.hover("kw:Pierce")
	assert_array(KeywordPopup.shown()).is_equal(["Pierce"])
	KeywordPopup.unhover("kw:Pierce")
	assert_array(KeywordPopup.shown()).is_empty()
	KeywordPopup.click("kw:Pierce")
	assert_str(KeywordPopup.pinned).is_equal("Pierce")
	# Hovering a keyword inside the pinned box shows its box beside it.
	KeywordPopup.hover("kw:Guard")
	assert_array(KeywordPopup.shown()).is_equal(["Pierce", "Guard"])
	KeywordPopup.unhover("kw:Guard")
	assert_array(KeywordPopup.shown()).is_equal(["Pierce"])
	# Clicking it pins that one instead.
	KeywordPopup.click("kw:Guard")
	assert_array(KeywordPopup.shown()).is_equal(["Guard"])
	KeywordPopup.dismiss()
	assert_array(KeywordPopup.shown()).is_empty()


func test_esc_and_a_click_elsewhere_unpin() -> void:
	var popup: KeywordPopup = auto_free(KeywordPopup.new())
	add_child(popup)
	KeywordPopup.click("kw:Pierce")
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	popup._input(esc)
	assert_str(KeywordPopup.pinned).is_empty()
	KeywordPopup.click("kw:Pierce")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(5000, 5000)
	popup._input(click)
	assert_str(KeywordPopup.pinned).is_empty()


func test_a_keyword_box_links_its_own_keywords() -> void:
	var b: PanelContainer = auto_free(KeywordPopup.box("Pierce"))
	var text: RichTextLabel = b.find_child("Text", true, false)
	# Pierce's lines name Defense; Reflect's name Guard, which links to its box.
	var reflect: PanelContainer = auto_free(KeywordPopup.box("Reflect"))
	var rt: RichTextLabel = reflect.find_child("Text", true, false)
	assert_str(rt.text).contains("[url=kw:Guard]")
	assert_int(rt.meta_clicked.get_connections().size()).is_equal(1)
	assert_object(text).is_not_null()
