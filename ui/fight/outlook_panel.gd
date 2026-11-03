class_name OutlookPanel
extends PanelContainer
## What the choice being looked at would lead to (combat rework S7), in the
## field's empty middle so the action dock never grows: where the bot lands
## on the timeline ("Next turn: 4th, in 120 ticks. Recovery 30%.") and the
## conditional combos ("11 now. 24 if Bolt puts Exposed on first (acts
## 4th)."), from ChoiceReadout. Plain style: information, nothing to click;
## the keywords link to the glossary. Hidden while nothing is looked at.

var landing_label: RichTextLabel
var combo_label: RichTextLabel


func _init() -> void:
	name = "Outlook"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyle.panel("plain")
	box.set_content_margin_all(UiStyle.space("s"))
	add_theme_stylebox_override("panel", box)
	var col := UiStyle.column("xs")
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var cap := UiStyle.caption(Label.new())
	cap.text = "IF YOU DO THIS"
	col.add_child(cap)
	landing_label = UiGlossary.rich("", PixelTheme.font_size("body"))
	landing_label.name = "Landing"
	landing_label.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(landing_label)
	combo_label = UiGlossary.rich("", PixelTheme.font_size("body"), UiStyle.role("hint"))
	combo_label.name = "Combo"
	combo_label.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(combo_label)


## Shows where the bot lands (`landing`, "" for none) and the conditional
## combos (`combos`, a line each); hides when both are empty.
func show_outlook(landing: String, combos: Array) -> void:
	UiGlossary.set_text(landing_label, landing)
	landing_label.visible = not landing.is_empty()
	UiGlossary.set_text(combo_label, "\n".join(combos))
	combo_label.visible = not combos.is_empty()
	visible = landing_label.visible or combo_label.visible


func hide_outlook() -> void:
	visible = false
