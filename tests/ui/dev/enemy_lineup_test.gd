extends GdUnitTestSuite
## The enemy lineup dev scene shows every unit type of every faction in every
## tier, idling.


func test_every_unit_appears_in_every_tier_playing_idle() -> void:
	var lineup: EnemyLineup = auto_free(load("res://ui/dev/enemy_lineup.tscn").instantiate())
	add_child(lineup)
	var expected := 0
	for faction: String in lineup.factions.factions:
		expected += lineup.factions.factions[faction].units.size() * lineup.factions.tiers.size()
	assert_int(lineup.sprites.size()).is_equal(expected)
	var shown := {}
	for sprite in lineup.sprites:
		assert_int(sprite.layer_count()).is_equal(1)
		assert_str(sprite.current_animation()).is_equal("idle")
		shown["%s/%s" % [sprite.unit_id, sprite.tier]] = true
	assert_int(shown.size()).is_equal(expected)
