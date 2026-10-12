class_name ActionButton
extends Button
## A map or menu action as an icon button whose label and cost always show:
##   [icon] Reinforce   [energy] 2
## Hovering adds the action's tooltip. It is a Button, so disabled and
## pressed work as usual.
##
##   var b := ActionButton.make("action_reinforce", "Reinforce", "material", 2)

var action_icon_id: String
var label_text: String
var cost_icon_id: String
var cost: Variant

var label: Label
var cost_stat: IconStat


static func make(p_icon_id: String, p_label: String, p_cost_icon_id := "", p_cost: Variant = null) -> ActionButton:
	var b := ActionButton.new()
	b.action_icon_id = p_icon_id
	b.label_text = p_label
	b._build()
	b.set_cost(p_cost_icon_id, p_cost)
	return b


func set_cost(p_cost_icon_id: String, p_cost: Variant) -> void:
	cost_icon_id = p_cost_icon_id
	cost = p_cost
	if cost_stat != null:
		cost_stat.get_parent().remove_child(cost_stat)
		cost_stat.queue_free()
		cost_stat = null
	if not cost_icon_id.is_empty() and cost != null:
		cost_stat = IconStat.make(cost_icon_id, cost)
		cost_stat.name = "Cost"
		cost_stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$Row.add_child(cost_stat)
	_retip()


func _build() -> void:
	name = "Action_%s" % action_icon_id
	focus_mode = Control.FOCUS_NONE
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.add_child(UiIcons.rect(action_icon_id))
	label = Label.new()
	label.name = "Label"
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	row.resized.connect(func() -> void: custom_minimum_size = row.get_combined_minimum_size() + Vector2(16, 8))
	custom_minimum_size = row.get_combined_minimum_size() + Vector2(16, 8)


func _retip() -> void:
	var numbers := "" if cost_stat == null else "Cost: %s %s" % [cost_stat.value_text(), UiIcons.display_name(cost_icon_id)]
	UiTooltip.attach(self, label_text, UiIcons.text(action_icon_id), numbers, action_icon_id)
