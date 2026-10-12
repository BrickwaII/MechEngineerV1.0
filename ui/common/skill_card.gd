class_name SkillCard
extends Button
## A skill as a card-like tile, like a Slay the Spire card: the name, the
## Energy cost in a corner badge, the effect in short words with numbers, and
## the rank. Its text always shows; hovering adds the tooltip with keywords.
## It is a Button, so toggle_mode, disabled and pressed work as usual.
##
##   var card := SkillCard.make("Beam", 3, "Deal 12 to one enemy. Pierce 20%.", "+2")
##   card.set_skill("Mega Beam", 4, "Deal 18 to one enemy.", "")

var skill_name: String
var cost: int
var effect: String
var rank: String
## Why the card cannot be played now, shown in its tooltip; "" when it can.
var problem: String

var name_label: Label
var effect_label: RichTextLabel
var rank_label: Label
var cost_badge: PanelContainer
var cost_label: Label


static func make(p_name: String, p_cost: int, p_effect: String, p_rank := "") -> SkillCard:
	var card := SkillCard.new()
	card.set_skill(p_name, p_cost, p_effect, p_rank)
	return card


## A rank as a card shows it: "" at rank 1, "+N" above it. Tier names
## (Mega, Ultra) are part of the skill's name, so they show there.
static func rank_text(step: int) -> String:
	return "+%d" % step if step > 0 else ""


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	custom_minimum_size = UiIcons.kit_vector("skill_card.size", Vector2(176, 96))
	var col := VBoxContainer.new()
	col.name = "Face"
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 6
	col.offset_top = 4
	col.offset_right = -6
	col.offset_bottom = -4
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	# Top row: the cost badge in the corner, the rank on the right.
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	cost_badge = PanelContainer.new()
	cost_badge.name = "CostBadge"
	cost_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := StyleBoxFlat.new()
	badge.bg_color = FeelData.color("bar_back")
	badge.border_color = FeelData.color(str(UiIcons.kit("skill_card.cost_color", "energy")))
	badge.set_border_width_all(1)
	badge.set_content_margin_all(2)
	badge.content_margin_right = 4
	cost_badge.add_theme_stylebox_override("panel", badge)
	top.add_child(cost_badge)
	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 2)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_badge.add_child(cost_row)
	cost_row.add_child(UiIcons.rect("energy"))
	cost_label = Label.new()
	cost_label.name = "Cost"
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_label.add_theme_color_override("font_color", FeelData.color(str(UiIcons.kit("skill_card.cost_color", "energy"))))
	cost_row.add_child(cost_label)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	rank_label = Label.new()
	rank_label.name = "Rank"
	rank_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTooltip._bold(rank_label, FeelData.color(str(UiIcons.kit("skill_card.rank_color", "preview"))))
	top.add_child(rank_label)
	# The name on its own line, smaller when it would not fit.
	name_label = Label.new()
	name_label.name = "Name"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTooltip._bold(name_label, FeelData.color("text_bright"))
	col.add_child(name_label)
	effect_label = RichTextLabel.new()
	effect_label.name = "Effect"
	effect_label.bbcode_enabled = true
	effect_label.fit_content = true
	effect_label.scroll_active = false
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_label.add_theme_font_size_override("normal_font_size", PixelTheme.font_size("small"))
	effect_label.add_theme_color_override("default_color", FeelData.color("text"))
	col.add_child(effect_label)


func set_skill(p_name: String, p_cost: int, p_effect: String, p_rank := "") -> void:
	skill_name = p_name
	cost = p_cost
	effect = p_effect
	rank = p_rank
	name_label.text = skill_name
	var room := custom_minimum_size.x - 16
	var fits := PixelTheme.font().get_string_size(skill_name, HORIZONTAL_ALIGNMENT_LEFT, -1, PixelTheme.font_size("body")).x <= room
	name_label.add_theme_font_size_override("font_size", PixelTheme.font_size("body" if fits else "small"))
	rank_label.text = rank
	rank_label.visible = not rank.is_empty()
	cost_label.text = str(cost)
	effect_label.text = UiGlossary.highlight(effect, UiTooltip._keyword_color())
	_retip()


## Sets why the card cannot be played; "" clears it.
func set_problem(p_problem: String) -> void:
	problem = p_problem
	_retip()


func _retip() -> void:
	var title := skill_name if rank.is_empty() else "%s %s" % [skill_name, rank]
	var body := effect if problem.is_empty() else "%s\n%s" % [effect, problem]
	UiTooltip.attach(self, title, body, "Energy: %d" % cost, "energy")
