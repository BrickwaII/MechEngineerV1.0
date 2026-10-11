class_name ReadoutStyle
extends RefCounted
## Sizes and colors of the battle screen's readouts (arrow badges, stat chips,
## the unit detail card, the NEXT bar hover), from data/feel/battle_readout.json.

const PATH := "res://data/feel/battle_readout.json"


## A number at a dotted path such as "badge.font_size".
static func number(path: String, fallback := 0.0) -> float:
	var node: Variant = _at(path)
	return float(node) if (node is float or node is int) else fallback


## A palette color named at a dotted path such as "badge.attack".
static func color(path: String, fallback := "text") -> Color:
	var node: Variant = _at(path)
	return FeelData.color(node if node is String else fallback)


static func text(path: String, fallback := "") -> String:
	var node: Variant = _at(path)
	return node if node is String else fallback


static func _at(path: String) -> Variant:
	var node: Variant = FeelData.table(PATH)
	for key in path.split("."):
		if not (node is Dictionary) or not node.has(key):
			return null
		node = node[key]
	return node
