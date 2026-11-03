extends GdUnitTestSuite
## Enemy archetypes (the plan's EnemyArchetypeDef) load from
## data/combat/archetypes.json and validate, and enemy table entries may name
## one (combat rework S1). S5 ships the Charger, Plated and Scaler; fights
## read them (tests/fight/archetypes/).


func _charger() -> Dictionary:
	return {"name": "Charger", "plating": 2, "intent_pattern": ["wind_up", "overload", "plan"],
		"scaling_percent_per_action": {"attack": 10}}


func test_the_shipped_archetypes_load_and_validate() -> void:
	var table := EnemyArchetypeTable.load_default()
	assert_object(table).is_not_null()
	assert_array(table.validate()).is_empty()
	for id in ["charger", "plated", "scaler"]:
		assert_bool(table.has(id)).is_true()
	var charger := table.get_archetype("charger")
	assert_array(charger.intent_pattern).contains_exactly(["strike", "wind_up", "ram"])
	assert_int(charger.wind_up_opponent_actions).is_greater_equal(1)
	assert_bool(charger.is_plated()).is_true()
	assert_int(table.get_archetype("plated").plating).is_greater(charger.plating)
	assert_bool(table.get_archetype("scaler").scales()).is_true()


## S5 (archetype-pools): every shipped archetype has an enemy in each tier,
## shared by every faction and drawn by the generic pools.
func test_every_archetype_fields_enemies_in_every_faction_and_the_generic_pools() -> void:
	var enemies := EnemyTable.load_default()
	var factions := FactionTable.load_default()
	var generic := {}
	for level: int in enemies.levels:
		for id: String in enemies.levels[level].pool:
			generic[enemies.archetype_of(id)] = true
	for archetype in ["charger", "plated", "scaler"]:
		assert_bool(generic.has(archetype)).override_failure_message(archetype).is_true()
		for tier in factions.tiers:
			var id := "%s_%s" % [archetype, tier]
			assert_str(enemies.archetype_of(id)).is_equal(archetype)
			assert_object(enemies.archetype_for(id)).is_not_null()
		for faction: String in factions.factions:
			assert_array(factions.pool(faction, FightRequest.MAX_DEFENSE_LEVEL, "medium")) \
				.contains(["%s_medium" % archetype])
	assert_array(enemies.validate(CombatTuning.load_default())).is_empty()


func test_only_archetype_enemies_name_an_archetype() -> void:
	var enemies := EnemyTable.load_default()
	for id: String in enemies.enemies:
		var archetype := enemies.archetype_of(id)
		assert_bool(archetype.is_empty() or id.begins_with(archetype + "_")).override_failure_message(id).is_true()


func test_from_dict_reads_every_field() -> void:
	var a := EnemyArchetype.from_dict("charger", _charger())
	assert_str(a.display_name).is_equal("Charger")
	assert_int(a.plating).is_equal(2)
	assert_bool(a.is_plated()).is_true()
	assert_array(a.intent_pattern).contains_exactly(["wind_up", "overload", "plan"])
	assert_bool(a.scales()).is_true()
	assert_int(a.scaling_percent_per_action["attack"]).is_equal(10)
	assert_array(a.validate(CombatTuning.load_default().skills.keys())).is_empty()


func test_from_dict_defaults_to_a_plain_enemy() -> void:
	var a := EnemyArchetype.from_dict("plain", {})
	assert_str(a.display_name).is_equal("plain")
	assert_bool(a.is_plated()).is_false()
	assert_array(a.intent_pattern).is_empty()
	assert_bool(a.scales()).is_false()
	assert_array(a.validate([])).is_empty()


func _problems(changes: Dictionary) -> Array[String]:
	var d := _charger()
	d.merge(changes, true)
	return EnemyArchetype.from_dict("test", d).validate(CombatTuning.load_default().skills.keys())


func test_validate_rejects_bad_fields() -> void:
	assert_array(_problems({})).is_empty()
	assert_array(_problems({"name": ""})).has_size(1)
	assert_array(_problems({"plating": -1})).has_size(1)
	assert_array(_problems({"intent_pattern": ["plan", "no_such_action"]})).has_size(1)
	assert_array(_problems({"intent_pattern": ["wind_up", "wind_up"]})).has_size(1)
	assert_array(_problems({"scaling_percent_per_action": {"hp": 10}})).has_size(1)
	assert_array(_problems({"scaling_percent_per_action": {"attack": 0}})).has_size(1)
	assert_array(_problems({"wind_up_opponent_actions": -1})).has_size(1)


func test_the_table_checks_intent_steps_against_the_tuning_actions() -> void:
	var table := EnemyArchetypeTable.from_dict({"_c": "x", "archetypes": {"_note": "y", "charger": _charger()}})
	assert_array(table.archetypes.keys()).contains_exactly(["charger"])
	assert_array(table.validate()).is_empty()
	var tuning := CombatTuning.load_default()
	tuning.skills.erase("overload")
	assert_array(table.validate(tuning)).has_size(1)


func test_an_enemy_may_name_a_known_archetype_only() -> void:
	var archetypes := EnemyArchetypeTable.load_default()
	archetypes.archetypes["charger"] = EnemyArchetype.from_dict("charger", _charger())
	var enemies := EnemyTable.load_default()
	var tuning := CombatTuning.load_default()
	var id: String = enemies.enemies.keys()[0]
	var entry: Dictionary = (enemies.enemies[id] as Dictionary).duplicate()
	enemies.enemies = enemies.enemies.duplicate()
	enemies.enemies[id] = entry
	entry["archetype"] = "charger"
	assert_str(enemies.archetype_of(id)).is_equal("charger")
	assert_array(enemies.validate(tuning, archetypes)).is_empty()
	entry["archetype"] = "no_such_archetype"
	assert_array(enemies.validate(tuning, archetypes)).contains(["enemy %s names unknown archetype no_such_archetype" % id])
