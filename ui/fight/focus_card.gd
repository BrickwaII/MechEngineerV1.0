class_name FocusCard
extends PanelContainer
## The chosen skill, lifted out of its tile into the dock's middle with
## everything about it (as Slay the Spire lifts a card, but beside the hand
## rather than over the board, so no target is ever covered): the cost, the name
## and rank, the effect with its keyword links, and the math for the target
## under the pointer (BattleMath). The board meanwhile marks every valid
## target with what the skill would do to it. A click on a target confirms;
## Esc or a right-click puts the card back.

var cost_label: Label
var name_label: Label
var effect_label: RichTextLabel
var math_label: RichTextLabel
var hint_label: Label
var skill_id := ""


func _init() -> void:
	name = "FocusCard"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyle.panel("overlay")
	box.border_color = UiStyle.role("hint")
	box.set_border_width_all(3)
	box.set_content_margin_all(UiStyle.space("s"))
	box.shadow_color = Color(UiStyle.role("hint"), 0.25)
	box.shadow_size = 12
	add_theme_stylebox_override("panel", box)
	custom_minimum_size = UiIcons.kit_vector("focus_card.size", Vector2(320, 0))
	var col := UiStyle.column("xs")
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var head := UiStyle.row("s")
	col.add_child(head)
	var badge := PanelContainer.new()
	var bbox := StyleBoxFlat.new()
	bbox.bg_color = FeelData.color("bar_back")
	bbox.border_color = FeelData.color("energy")
	bbox.set_border_width_all(1)
	bbox.set_content_margin_all(UiStyle.space("xs"))
	badge.add_theme_stylebox_override("panel", bbox)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(badge)
	var cost_row := UiStyle.row("xs")
	badge.add_child(cost_row)
	cost_row.add_child(UiIcons.rect("energy"))
	cost_label = UiStyle.label("", "info")
	cost_label.name = "Cost"
	cost_row.add_child(cost_label)
	name_label = Label.new()
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTooltip._bold(name_label, UiStyle.role("title"))
	head.add_child(name_label)
	effect_label = UiGlossary.rich("", PixelTheme.font_size("body"))
	effect_label.name = "Effect"
	effect_label.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(effect_label)
	math_label = RichTextLabel.new()
	math_label.name = "Math"
	math_label.bbcode_enabled = true
	math_label.fit_content = true
	math_label.scroll_active = false
	math_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	math_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	math_label.add_theme_font_size_override("normal_font_size", PixelTheme.font_size("body"))
	col.add_child(math_label)
	hint_label = UiStyle.label("", "text_quiet")
	hint_label.name = "Hint"
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint_label)


## Shows the card for `p_skill_id`: `face` is BattleScreen.skill_card_face(),
## `math` formula lines (UiFormula or String), `hint` the step's words. The
## card lifts in the first time it shows for a skill.
func show_skill(p_skill_id: String, face: Dictionary, cost: int, math: Array, hint: String) -> void:
	var fresh := not visible or p_skill_id != skill_id
	skill_id = p_skill_id
	cost_label.text = str(cost)
	name_label.text = face["name"] if str(face.get("rank", "")).is_empty() else "%s %s" % [face["name"], face["rank"]]
	UiGlossary.set_text(effect_label, str(face.get("effect", "")))
	math_label.text = "\n".join(UiTooltip.math_lines(math))
	math_label.visible = not math.is_empty()
	hint_label.text = hint
	visible = true
	if fresh:
		_lift()


func hide_card() -> void:
	visible = false
	skill_id = ""


func _lift() -> void:
	# Rises into place: grows from a little smaller and fades in.
	pivot_offset = Vector2(size.x / 2.0, size.y)
	if not is_inside_tree() or GameSettings.shared().skips_animations():
		scale = Vector2.ONE
		modulate.a = 1.0
		return
	scale = Vector2.ONE * 0.92
	modulate.a = 0.0
	FeelTween.to(self, "scale", Vector2.ONE, "ui")
	FeelTween.to(self, "modulate:a", 1.0, "ui")
