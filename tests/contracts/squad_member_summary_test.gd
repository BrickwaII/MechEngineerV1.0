extends GdUnitTestSuite


func test_holds_its_fields() -> void:
	var stats := UnitStats.new(30, 8, 3, 7, 2, 10)
	var member := SquadMemberSummary.new("b1", "Bolt", 20, 30, "aggressive", stats)
	assert_str(member.id).is_equal("b1")
	assert_str(member.display_name).is_equal("Bolt")
	assert_int(member.hp).is_equal(20)
	assert_int(member.max_hp).is_equal(30)
	assert_str(member.personality_tag).is_equal("aggressive")
	assert_object(member.stats).is_same(stats)


func test_always_has_stats() -> void:
	assert_object(SquadMemberSummary.new().stats).is_not_null()


func test_round_trips_through_a_resource_file_with_its_stats() -> void:
	var path := create_temp_dir("contracts").path_join("member.tres")
	var member := SquadMemberSummary.new("b1", "Bolt", 20, 30, "aggressive", UnitStats.new(30, 8, 3, 7, 2, 10))
	assert_int(ResourceSaver.save(member, path)).is_equal(OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SquadMemberSummary
	assert_str(loaded.display_name).is_equal("Bolt")
	assert_int(loaded.stats.attack).is_equal(8)
