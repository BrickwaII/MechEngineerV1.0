class_name Flag
extends PanelContainer
## A flag: a small badge for one characteristic (Boss, Elite, Low HP, New,
## Fortified, ...). Every flag in the game looks the same: an icon and a short
## word on a fill tinted with its color role, no border (borders are for
## things you click). Flags sit on a card's edge, never over its art.
##
##   Flag.of("boss")                                  # from data/ui/flags.json
##   Flag.make("Charging", "status_charging", "info", "Acts big next turn.")
##   Flag.of("low_hp", true)                          # compact: icon only
##
## Hover shows the standard tooltip with its line.

const FLAGS_PATH := "res://data/ui/flags.json"

var label_text: String
var icon_id: String
var color_role: String
var tip: String
var compact := false

var icon_rect: TextureRect
var label: Label


## A flag from the catalog in data/ui/flags.json; an unknown id gets a
## neutral flag named after it.
static func of(id: String, p_compact := false) -> Flag:
	var e: Dictionary = catalog().get(id, {})
	var f := make(str(e.get("label", id.capitalize())), str(e.get("icon", "")), str(e.get("role", "neutral")),
		str(e.get("text", "")), p_compact)
	f.name = "Flag_%s" % id
	return f


static func make(p_label: String, p_icon_id := "", p_role := "neutral", p_tip := "", p_compact := false) -> Flag:
	var f := Flag.new()
	f.label_text = p_label
	f.icon_id = p_icon_id
	f.color_role = p_role
	f.tip = p_tip
	f.compact = p_compact and not p_icon_id.is_empty()
	f._build()
	return f


static func catalog() -> Dictionary:
	return FeelData.table(FLAGS_PATH).get("flags", {})


## The fill a flag of `role` uses: its color, mostly sunk into the panel.
static func fill_color(role: String) -> Color:
	return FeelData.color("panel").lerp(UiStyle.role(role), 0.25)


## The text color: the role's color, lifted so it reads on the fill.
static func text_color(role: String) -> Color:
	return UiStyle.role(role).lerp(Color.WHITE, 0.15)


func _build() -> void:
	if name.is_empty() or name.begins_with("@"):
		name = "Flag_%s" % label_text.to_snake_case()
	mouse_filter = Control.MOUSE_FILTER_PASS
	var box := StyleBoxFlat.new()
	box.anti_aliasing = false
	box.bg_color = fill_color(color_role)
	var pad := UiIcons.kit_vector("flag.padding", Vector2(4, 2))
	box.content_margin_left = pad.x
	box.content_margin_right = pad.x + (0.0 if compact else 2.0)
	box.content_margin_top = pad.y
	box.content_margin_bottom = pad.y
	add_theme_stylebox_override("panel", box)
	custom_minimum_size.y = float(UiIcons.kit("flag.height", 28))
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", UiStyle.space("xs"))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	if not icon_id.is_empty():
		icon_rect = UiIcons.rect(icon_id)
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon_rect)
	label = Label.new()
	label.name = "Label"
	label.text = label_text
	label.visible = not compact
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", text_color(color_role))
	row.add_child(label)
	UiTooltip.attach(self, label_text, tip, "", icon_id)


## A row of flags for a card's edge, wrapping when it runs out of room.
static func row(flags: Array) -> HFlowContainer:
	var r := HFlowContainer.new()
	r.name = "Flags"
	r.add_theme_constant_override("h_separation", UiStyle.space("xs"))
	r.add_theme_constant_override("v_separation", UiStyle.space("xs"))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for f: Control in flags:
		r.add_child(f)
	return r
