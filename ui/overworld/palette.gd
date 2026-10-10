extends RefCounted
## Overworld colors, taken from the layout mockup.

const BACKGROUND := Color("#0b121b")
const MAP_BACKGROUND := Color("#0d1520")
const MAP_GRID_LINE := Color("#142030")
const WATER := Color("#0f2334")
const INSET_OWNED := Color("#35c2b0")
const INSET_HOSTILE := Color("#5a6273")
const BAR_BACKGROUND := Color("#0f1824")
const PANEL := Color("#111b27")
const RULE := Color("#223244")
const TEXT := Color("#dbe6f0")
const TEXT_BRIGHT := Color("#f1f6fa")
const TEXT_DIM := Color("#8aa0b4")
const TEXT_BODY := Color("#a9bccd")
const LABEL_BACK := Color(8 / 255.0, 14 / 255.0, 22 / 255.0, 0.78)

const OWNED := Color("#1d8a80")
const OWNED_SELECTED := Color("#2fb8a9")
const IN_RANGE := Color("#8a4b43")
const IN_RANGE_SELECTED := Color("#b0604f")
const OUT_OF_REACH := Color("#3a3a48")
const OUT_OF_REACH_SELECTED := Color("#585770")

const ACCENT := Color("#35c2b0")
const ACCENT_TEXT := Color("#06201c")
const DEFENSE := Color("#ffb26b")
const DEFENSE_TEXT := Color("#ffc48f")
const WARNING := Color("#f2b84b")
const DANGER := Color("#ff6b5e")
const TAG_WARNING := Color("#f5d06b")
const TAG_DANGER := Color("#ff9a8f")
const ATTACK_BUTTON := Color("#f08a46")
const ATTACK_TEXT := Color("#1c0e05")
const DISABLED := Color("#243445")
const TIME_FILL := Color("#5b87ad")
const TIME_GHOST := Color("#ffd9a8")
const TIME_GHOST_DARK := Color("#9a6a35")

const POWER := Color("#f2b84b")
const ENERGY := Color("#5cc8ff")
const MATERIAL := Color("#b99cff")

## Colors for the odds bands in tuning order, best first.
const ODDS := [Color("#7be7a8"), Color("#f5d96e"), Color("#ffb26b"), Color("#ff8277")]


static func resource_color(key: String) -> Color:
	match key:
		MapRegion.POWER:
			return POWER
		MapRegion.ENERGY:
			return ENERGY
	return MATERIAL


static func region_fill(standing: int, selected: bool) -> Color:
	match standing:
		Campaign.Standing.OWNED:
			return OWNED_SELECTED if selected else OWNED
		Campaign.Standing.IN_RANGE:
			return IN_RANGE_SELECTED if selected else IN_RANGE
	return OUT_OF_REACH_SELECTED if selected else OUT_OF_REACH
