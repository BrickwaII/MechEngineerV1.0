extends GdUnitTestSuite
## Enemy archetypes (the plan's EnemyArchetypeDef) load from
## data/combat/archetypes.json and validate, and enemy table entries may name
## one (combat rework S1). No fight reads an archetype yet.


func _charger() -> Dictionary:
	return {"name": "Charger", "plating": 2, "intent_pattern": ["wind_up", "overload", "plan"],
		"scaling_percent_per_action": {"attack": 10}}


func test_the_shipped_archetypes_load_and_validate() -> void:
	var table := EnemyArchetypeTable.load_default()
	assert_object(table).is_not_null()
	assert_array(table.validate()).is_empty()


func test_no_shipped_enemy_names_an_archetype_yet() -> void:
	var enemies := EnemyTable.load_default()
	for id: String in enemies.enemies:
		assert_str(enemies.archetype_of(id)).is_empty()


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


func test_the_table_checks_intent_steps_against_the_tuning_actions() -> void:
	var table := EnemyArchetypeTable.from_dict({"_c": "x", "archetypes": {"_note": "y", "charger": _charger()}})
	assert_array(table.archetypes.keys()).contains_exactly(["charger"])
	assert_array(table.validate()).is_empty()
	var tuning := CombatTuning.load_default()
	tuning.skills.erase("overload")
	assert_array(table.validate(tuning)).has_size(1)


func test_an_enemy_may_name_a_known_archetype_only() -> void:
	var archetypes := EnemyArchetypeTable.from_dict({"archetypes": {"charger": _charger()}})
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
