extends RefCounted
## Pins the fight switches the combat-economy pass (R2-C) changed back to
## their old options, for suites that test mechanics with numbers worked out
## under them: speed-range wide (gauge per tick = speed), strike-cost free,
## tag-weight per_action and difficulty-curve flat. Every other switch keeps
## its data default. Call pin() in a suite's before() and unpin() in after():
##
##   const Legacy := preload("res://tests/fight/legacy_switches.gd")
##   func before() -> void:
##       Legacy.pin()
##   func after() -> void:
##       Legacy.unpin()
##
## The new options have their own tests.

const OLD := {
	"speed-range": "wide",
	"strike-cost": "free",
	"tag-weight": "per_action",
	"difficulty-curve": "flat",
}


static func pin() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FightVariants.DEFAULT_PATH))
	for entry: Dictionary in data.decisions:
		if OLD.has(entry.get("id", "")):
			entry["default"] = OLD[entry.id]
	FightVariants._cached_defaults = data


static func unpin() -> void:
	FightVariants._cached_defaults = {}
