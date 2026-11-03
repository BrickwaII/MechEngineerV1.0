extends HFlowContainer
## A unit's statuses as flags (ui/README.md rule 9): the status icon and its
## name with its number ("Guard 40%"), on the card's edge, color AND shape,
## the full word in the hover tooltip. Icons are the status_<id> ids in
## data/ui/icons.json; `compact` shows icons only (name on hover).
##
##   guard           shield    "GUARD 40%"
##   brace           wall      "BRACE 6"     (absorbs 6 more, until its next action)
##   exposed         crack     "EXPOSED +50%" (the next hit deals 50% more; ends at its next action)
##   plating         plate     "PLATING 3/4" (drawn as pips: 3 whole, 1 broken)
##   staggered       spiral    "STAGGERED +50%" (loses its next turn; hits deal 50% more)
##   wind_up         fist      "WIND-UP Ram"  (a committed hit lands when its wait ends)
##   charging        bolt      "CHARGE >6"   (in a wait, filling toward a cost)
##   waiting         hourglass "WAIT"        (an exact wait, or a telegraphed wait)
##   low_energy      battery   "LOW EN"      (cannot afford any skill that costs energy)
##   down            cross     "DOWN"
##   intent_changed  diamond   "CHANGED"     (its intent was revised this turn)

const IDS: Array[String] = ["guard", "brace", "exposed", "plating", "staggered", "wind_up", "charging", "waiting",
	"low_energy", "down", "intent_changed"]
const ICON_SCALE := 2
## Status id -> its flag's color role.
const ROLES := {"guard": "info", "brace": "info", "exposed": "bad", "plating": "neutral", "staggered": "caution",
	"wind_up": "bad", "charging": "info", "waiting": "neutral", "low_energy": "caution", "down": "neutral",
	"intent_changed": "rare"}
## Status id -> its icon id, where it is not "status_<id>".
const ICON_IDS := {"wind_up": "intent_wind_up"}


## Status id -> its word, for what shows now.
var shown: Dictionary[String, String] = {}
## Where the flags go: this row by default, or another flow (a card's one
## flag row), so all of a card's flags wrap together.
var target: Container
## The flags shown now.
var flags: Array[Flag] = []

## The statuses changed (the card puts its flags back in order).
signal changed
## Icons only, the name on hover.
var compact := false

static var _icons := {}


func _init() -> void:
	add_theme_constant_override("h_separation", UiStyle.space("xs"))
	add_theme_constant_override("v_separation", UiStyle.space("xs"))
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
	for f in flags:
		if is_instance_valid(f):
			if f.get_parent() != null:
				f.get_parent().remove_child(f)
			f.queue_free()
	flags.clear()
	var into: Container = target if target != null else self
	for id: String in shown:
		var icon := icon_id(id)
		var number := number_of(shown[id])
		var label := UiIcons.display_name(icon)
		if id == "plating":
			# The pips say it; the numbers are in the tooltip.
			label = ""
		elif id == "wind_up":
			label = "%s %s" % [label, shown[id].trim_prefix("WIND-UP").strip_edges()]
		elif not number.is_empty():
			label = "%s %s" % [label, number]
		var flag := Flag.make(label, icon, ROLES.get(id, "neutral"), UiIcons.text(icon), compact)
		flag.name = "Status_%s" % id
		if id == "plating":
			flag.label.visible = false
			var pips := pips_of(shown[id])
			flag.get_node("Row").add_child(PlatingPips.make(pips.x, pips.y))
		UiTooltip.attach(flag, UiIcons.display_name(icon), UiIcons.text(icon), shown[id], icon)
		into.add_child(flag)
		flags.append(flag)
	changed.emit()


## The icon id of status `id`.
static func icon_id(id: String) -> String:
	return ICON_IDS.get(id, "status_" + id)


## "PLATING 3/4" -> Vector2i(3, 4): pips whole and at most.
static func pips_of(word: String) -> Vector2i:
	var m := RegEx.create_from_string("(\\d+)/(\\d+)").search(word)
	if m == null:
		return Vector2i.ZERO
	return Vector2i(int(m.get_string(1)), int(m.get_string(2)))


## The part of a status word the card shows: the tokens with a digit.
## "GUARD 40%" -> "40%", "CHARGE >6" -> ">6", "LOW EN" -> "".
static func number_of(word: String) -> String:
	var parts: Array[String] = []
	for token in word.split(" ", false):
		if RegEx.create_from_string("\\d").search(token) != null:
			parts.append(token)
	return " ".join(parts)


func text() -> String:
	return " · ".join(shown.values())


static func icon_for(id: String) -> Texture2D:
	if not _icons.has(id):
		_icons[id] = UiIcons.texture(icon_id(id))
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
		"exposed", "wind_up":
			return FeelData.color("danger")
		"staggered":
			return FeelData.color("warning")
		"brace":
			return FeelData.color("accent")
	return FeelData.color("text_dim")


## Plating as a row of pips: whole ones filled, broken ones hollow. Drawn,
## not text, so it reads at a glance (ui/README.md rule 1).
class PlatingPips extends Control:
	## A pip's side and the gap between pips, in pixels.
	const PIP := 8
	const PIP_GAP := 2
	var whole := 0
	var most := 0

	static func make(p_whole: int, p_most: int) -> PlatingPips:
		var p := PlatingPips.new()
		p.name = "Pips"
		p.whole = p_whole
		p.most = maxi(p_whole, p_most)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.custom_minimum_size = Vector2(maxi(1, p.most) * (PIP + PIP_GAP) - PIP_GAP, PIP + 2)
		return p

	func _draw() -> void:
		var y := (size.y - PIP) / 2.0
		for i in most:
			var r := Rect2(i * (PIP + PIP_GAP), y, PIP, PIP)
			if i < whole:
				draw_rect(r, FeelData.color("sprite_metal_light"))
				draw_rect(r, FeelData.color("sprite_outline"), false, 1.0)
			else:
				draw_rect(r, FeelData.color("bar_back"))
				draw_rect(r, FeelData.color("danger").darkened(0.2), false, 1.0)
