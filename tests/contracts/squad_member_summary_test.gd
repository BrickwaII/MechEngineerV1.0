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


func test_has_no_skills_by_default() -> void:
	assert_array(SquadMemberSummary.new().skills).is_empty()


func test_holds_its_skills_in_order() -> void:
	var skills: Array[Dictionary] = [
		SquadMemberSummary.make_skill("Patch Up", "heal_single", 2),
		SquadMemberSummary.make_skill("Brace", "guard_self"),
	]
	var member := SquadMemberSummary.new("b1", "Bolt", 20, 30, "supportive", null, skills)
	assert_int(member.skills.size()).is_equal(2)
	assert_str(member.skills[0][SquadMemberSummary.SKILL_NAME]).is_equal("Patch Up")
	assert_str(member.skills[0][SquadMemberSummary.SKILL_EFFECT_ID]).is_equal("heal_single")
	assert_int(member.skills[0][SquadMemberSummary.SKILL_LEVEL]).is_equal(2)
	assert_int(member.skills[1][SquadMemberSummary.SKILL_LEVEL]).is_equal(1)


func test_changing_the_passed_skills_does_not_change_the_summary() -> void:
	var skills: Array[Dictionary] = [SquadMemberSummary.make_skill("Strike", "damage_single")]
	var member := SquadMemberSummary.new("b1", "Bolt", 20, 30, "aggressive", null, skills)
	skills[0][SquadMemberSummary.SKILL_LEVEL] = 9
	skills.append(SquadMemberSummary.make_skill("Brace", "guard_self"))
	assert_int(member.skills.size()).is_equal(1)
	assert_int(member.skills[0][SquadMemberSummary.SKILL_LEVEL]).is_equal(1)


func test_round_trips_its_skills_through_a_resource_file() -> void:
	var path := create_temp_dir("contracts").path_join("member_skills.tres")
	var skills: Array[Dictionary] = [SquadMemberSummary.make_skill("Patch Up", "heal_single", 3)]
	var member := SquadMemberSummary.new("b1", "Bolt", 20, 30, "supportive", null, skills)
	assert_int(ResourceSaver.save(member, path)).is_equal(OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SquadMemberSummary
	assert_int(loaded.skills.size()).is_equal(1)
	assert_str(loaded.skills[0][SquadMemberSummary.SKILL_EFFECT_ID]).is_equal("heal_single")
	assert_int(loaded.skills[0][SquadMemberSummary.SKILL_LEVEL]).is_equal(3)
