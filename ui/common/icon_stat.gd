class_name IconStat
extends HBoxContainer
## An icon with a number beside it and a tooltip: the way every stat,
## resource and region property shows. The icon id names its picture, name,
## color and tooltip lines in data/ui/icons.json.
##
##   var atk := IconStat.make("atk", 12)
##   atk.set_value(14)
##   IconStat.make("time", "3/10", "Days left. Attacking costs 1.")

var icon_id: String
## int, float, String or null (icon only).
var value: Variant
## Extra tooltip lines; "" uses the icon's own lines from icons.json.
var tip_text: String

var icon_rect: TextureRect
var value_label: Label


static func make(p_icon_id: String, p_value: Variant = null, p_tip_text := "") -> IconStat:
	var s := IconStat.new()
	s.icon_id = p_icon_id
	s.tip_text = p_tip_text
	s._build()
	s.set_value(p_value)
	return s


## The number as shown: whole numbers for floats, "" for null.
static func format_value(v: Variant) -> String:
	if v == null:
		return ""
	if v is float:
		return str(roundi(v))
	return str(v)


func set_value(p_value: Variant) -> void:
	value = p_value
	value_label.text = format_value(value)
	value_label.visible = not value_label.text.is_empty()
	_retip()


func set_tip_text(p_tip_text: String) -> void:
	tip_text = p_tip_text
	_retip()


func value_text() -> String:
	return value_label.text


func _build() -> void:
	name = "IconStat_%s" % icon_id
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_STOP
	icon_rect = UiIcons.rect(icon_id)
	add_child(icon_rect)
	value_label = Label.new()
	value_label.name = "Value"
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.add_theme_color_override("font_color", FeelData.color("text_bright"))
	add_child(value_label)


func _retip() -> void:
	var lines := tip_text if not tip_text.is_empty() else UiIcons.text(icon_id)
	var numbers := "" if value_text().is_empty() else "%s: %s" % [UiIcons.display_name(icon_id), value_text()]
	UiTooltip.attach(self, UiIcons.display_name(icon_id), lines, numbers, icon_id)
