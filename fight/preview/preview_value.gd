class_name PreviewValue
extends RefCounted
## A number the preview reports: either known exactly, or unknown because it
## depends on randomness. The UI shows an unknown value as "?" and never as a
## made-up number.

const UNKNOWN_TEXT := "?"

var known: bool
## Meaningful only when known.
var value: int


func _init(p_known := true, p_value := 0) -> void:
	known = p_known
	value = p_value if p_known else 0


static func of(p_value: int) -> PreviewValue:
	return PreviewValue.new(true, p_value)


static func unknown() -> PreviewValue:
	return PreviewValue.new(false)


func is_unknown() -> bool:
	return not known


func equals(other: PreviewValue) -> bool:
	return other != null and known == other.known and value == other.value


## The value as the UI shows it: the number, or "?".
func text() -> String:
	return str(value) if known else UNKNOWN_TEXT


func _to_string() -> String:
	return text()
