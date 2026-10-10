class_name ScreenFeel
extends RefCounted
## Timings for the map, draft, post-fight readout and screen transitions, from
## data/feel/screens.json. Durations follow the animation speed setting like
## the rest of the feel kit: shorter at 1.5x and 2x, zero on skip.
##
##     ScreenFeel.number("map.ring_pulse_px")
##     ScreenFeel.seconds("draft.flip_ms")

const PATH := "res://data/feel/screens.json"


static func table() -> Dictionary:
	return FeelData.table(PATH)


## The value at a dotted path such as "map.hover_ms", or `fallback`.
static func value(path: String, fallback: Variant = null) -> Variant:
	var node: Variant = table()
	for key in path.split("."):
		if not (node is Dictionary) or not node.has(key):
			return fallback
		node = node[key]
	return node


static func number(path: String, fallback := 0.0) -> float:
	var v: Variant = value(path)
	return float(v) if (v is float or v is int) else fallback


## A *_ms value in seconds after the animation speed setting.
static func seconds(path: String, settings: GameSettings = null) -> float:
	settings = settings if settings else GameSettings.shared()
	return settings.scale_seconds(number(path) / 1000.0)
