extends GdUnitTestSuite
## FactionLookup: the enemy faction for the territory panel, or nothing.

const DATA := {
	"factions": {
		"rustborn": {"name": "Rustborn", "color": "#c86b3c", "icon": "res://assets/ui/icons/status_guard.png"},
		"choir": {"name": "Signal Choir", "color": "not a color"},
		"nameless": {"color": "#ffffff"},
	},
	"by_region": {"lake_washington_12": {"bellevue": "choir", "renton": "nameless"}},
	"by_act": {"0": "rustborn"},
}


func _lookup() -> FactionLookup:
	var lookup := FactionLookup.new()
	lookup.read(DATA)
	return lookup


func test_a_region_entry_wins_over_the_act() -> void:
	var f := _lookup().faction_for("lake_washington_12", 0, "bellevue")
	assert_str(f["name"]).is_equal("Signal Choir")
	# A bad color is dropped rather than guessed.
	assert_object(f["color"]).is_null()


func test_the_act_entry_covers_the_other_regions() -> void:
	var f := _lookup().faction_for("lake_washington_12", 0, "kirkland")
	assert_str(f["id"]).is_equal("rustborn")
	assert_object(f["color"]).is_equal(Color("#c86b3c"))
	assert_object(f["icon"]).is_not_null()


func test_missing_data_gives_no_faction() -> void:
	assert_dict(_lookup().faction_for("north_america_33", 1, "oregon")).is_empty()
	assert_dict(_lookup().faction_for("lake_washington_12", 0, "renton")).is_empty()
	assert_dict(FactionLookup.new().faction_for("any", 0, "any")).is_empty()
	# Until P4's FactionTable lands the default lookup is empty.
	if not ResourceLoader.exists(FactionLookup.TABLE_PATH):
		assert_dict(FactionLookup.load_default().faction_for("lake_washington_12", 0, "bellevue")).is_empty()


class TableFaction:
	extends RefCounted
	var display_name := "Hive"
	var color := Color("#00ff00")


func test_objects_from_the_table_read_like_dictionaries() -> void:
	var f := FactionLookup.normalize(TableFaction.new())
	assert_str(f["name"]).is_equal("Hive")
	assert_object(f["color"]).is_equal(Color("#00ff00"))
	assert_dict(FactionLookup.normalize(null)).is_empty()
	assert_dict(FactionLookup.normalize({"color": "#fff"})).is_empty()
