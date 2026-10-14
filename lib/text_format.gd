class_name TextFormat
extends RefCounted
## Number text shared by the map, the stakes and the screens.


## A whole number bare ("10"), anything else to one decimal ("2.5").
static func short_number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
