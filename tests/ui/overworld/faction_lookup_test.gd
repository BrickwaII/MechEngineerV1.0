extends GdUnitTestSuite
## FactionLookup: the enemy faction for the territory panel, from P4's
## FactionTable, or nothing.


func _lookup(rule := FightVariants.FACTIONS_BY_ACT) -> FactionLookup:
	var lookup := FactionLookup.load_default()
	lookup.rule_source = func() -> String: return rule
	return lookup


func test_a_shipped_region_names_its_faction_with_color_and_icon() -> void:
	var table := FactionTable.load_default()
	var region := "bellevue"
	var id := table.faction_for_region(region)
	assert_str(id).is_not_empty()
	var f := _lookup().faction_for(region)
	assert_str(f["id"]).is_equal(id)
	assert_str(f["name"]).is_equal(table.faction_name(id))
	assert_object(f["color"]).is_equal(table.faction_color(id))
	assert_object(f["icon"]).is_not_null()


func test_every_region_of_every_act_map_has_a_faction() -> void:
	var lookup := _lookup()
	for path in ["res://data/regions/lake_washington_12.json", "res://data/regions/north_america_33.json",
			"res://data/regions/world_20.json"]:
		for region: MapRegion in RegionMap.load_file(path).regions:
			assert_dict(lookup.faction_for(region.id)).override_failure_message(region.id).is_not_empty()


func test_the_generic_rule_and_unknown_regions_show_nothing() -> void:
	assert_dict(_lookup(FightVariants.FACTIONS_GENERIC).faction_for("bellevue")).is_empty()
	assert_dict(_lookup().faction_for("hydro_dam")).is_empty()
	assert_dict(FactionLookup.new().faction_for("bellevue")).is_empty()
