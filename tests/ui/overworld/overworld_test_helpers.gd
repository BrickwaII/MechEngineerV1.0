class_name OverworldTestHelpers
extends RefCounted
## Shared lookups for the overworld screen tests.


## True when a label or button in the territory panel contains `part`.
static func panel_has_text(screen: Node, part: String) -> bool:
	for node in screen._panel.find_children("*", "", true, false):
		if (node is Label or node is Button) and part in node.text:
			return true
	return false
