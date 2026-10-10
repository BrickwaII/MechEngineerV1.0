extends HBoxContainer
## A unit's statuses as icons with a short word each: color AND shape AND a
## word, never color alone. Icons are assets/ui/icons/status_<id>.png.
##
##   guard           shield    "GUARD 40%"
##   charging        bolt      "CHARGE >6"   (in a wait, filling toward a cost)
##   waiting         hourglass "WAIT"        (an exact wait, or a telegraphed wait)
##   low_energy      battery   "LOW EN"      (cannot afford any skill that costs energy)
##   down            cross     "DOWN"
##   intent_changed  diamond   "CHANGED"     (its intent was revised this turn)

const IDS: Array[String] = ["guard", "charging", "waiting", "low_energy", "down", "intent_changed"]
const ICON_SCALE := 2

## Status id -> its word, for what shows now.
var shown: Dictionary[String, String] = {}

static var _icons := {}


func _init() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 12 * ICON_SCALE)


## Shows `statuses` (status id -> word) in IDS order.
func show_statuses(statuses: Dictionary) -> void:
	var next: Dictionary[String, String] = {}
	for id in IDS:
		if statuses.has(id):
			next[id] = str(statuses[id])
	if next == shown:
		return
	shown = next
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for id: String in shown:
		var item := HBoxContainer.new()
		item.name = "Status_%s" % id
		item.add_theme_constant_override("separation", 2)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = icon_for(id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(12, 12) * ICON_SCALE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(icon)
		var label := Label.new()
		label.text = shown[id]
		label.theme_type_variation = &"SmallLabel"
		label.add_theme_color_override("font_color", color_for(id))
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(label)
		add_child(item)


func text() -> String:
	return " · ".join(shown.values())


static func icon_for(id: String) -> Texture2D:
	if not _icons.has(id):
		_icons[id] = load("res://assets/ui/icons/status_%s.png" % id)
	return _icons[id]


static func color_for(id: String) -> Color:
	match id:
		"guard":
			return FeelData.color("selected")
		"charging":
			return FeelData.color("energy")
		"low_energy":
			return FeelData.color("warning")
		"down":
			return FeelData.color("danger")
		"intent_changed":
			return FeelData.color("changed")
	return FeelData.color("text_dim")
