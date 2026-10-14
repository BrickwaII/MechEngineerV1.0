extends HFlowContainer
## A unit's statuses as flags (ui/README.md rule 9): the status icon and its
## name with its number ("Guard 40%"), on the card's edge, color AND shape,
## the full word in the hover tooltip. Icons are the status_<id> ids in
## data/ui/icons.json; `compact` shows icons only (name on hover).
##
##   guard           shield    "GUARD 40%"
##   charging        bolt      "CHARGE >6"   (in a wait, filling toward a cost)
##   waiting         hourglass "WAIT"        (an exact wait, or a telegraphed wait)
##   low_energy      battery   "LOW EN"      (cannot afford any skill that costs energy)
##   down            cross     "DOWN"
##   intent_changed  diamond   "CHANGED"     (its intent was revised this turn)

const IDS: Array[String] = ["guard", "charging", "waiting", "low_energy", "down", "intent_changed"]
const ICON_SCALE := 2
## Status id -> its flag's color role.
const ROLES := {"guard": "info", "charging": "info", "waiting": "neutral", "low_energy": "caution",
	"down": "neutral", "intent_changed": "rare"}

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
		var number := number_of(shown[id])
		var label := UiIcons.display_name("status_" + id)
		if not number.is_empty():
			label = "%s %s" % [label, number]
		var flag := Flag.make(label, "status_" + id, ROLES.get(id, "neutral"), UiIcons.text("status_" + id), compact)
		flag.name = "Status_%s" % id
		UiTooltip.attach(flag, UiIcons.display_name("status_" + id), UiIcons.text("status_" + id), shown[id], "status_" + id)
		into.add_child(flag)
		flags.append(flag)
	changed.emit()


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
