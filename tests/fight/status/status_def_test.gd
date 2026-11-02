extends GdUnitTestSuite
## Status definitions (StatusDef) load from data/combat/statuses.json and
## validate (combat rework S1).


func test_the_shipped_statuses_load_and_validate() -> void:
	var table := StatusTable.load_default()
	assert_object(table).is_not_null()
	assert_array(table.validate()).is_empty()


func test_exposed_matches_the_design() -> void:
	# Deep dive: takes +50% from the next hit; consumed by a hit, or ends at
	# the holder's next action.
	var s := StatusTable.load_default().get_status("exposed")
	assert_object(s).is_not_null()
	assert_str(s.display_name).is_equal("Exposed")
	assert_str(s.effect).is_equal(StatusDef.EFFECT_DAMAGE_TAKEN_PERCENT)
	assert_int(s.amount).is_equal(50)
	assert_int(s.max_stacks).is_equal(1)
	assert_str(s.expiry).is_equal(StatusDef.EXPIRY_HOLDER_NEXT_ACTION)
	assert_bool(s.is_consumed_by(StatusDef.CONSUMED_BY_HIT)).is_true()
	assert_bool(s.is_consumed_by(StatusDef.CONSUMED_BY_PAYOFF)).is_false()


func test_only_shred_applies_a_status_and_only_heavy_strike_has_a_payoff() -> void:
	# S3 lands the first setup and payoff on content no draft uses yet
	# (TODO(decision: shred-in-drafts)), plus Heavy Strike's payoff, which
	# changes nothing until something applies Exposed.
	for a: CombatSkill in ActionTable.load_default().actions.values():
		assert_str(a.applies_status).is_equal("exposed" if a.id == "shred" else "")
		assert_str(a.payoff_condition).is_equal("exposed" if a.id == "heavy_strike" else "")


func test_from_dict_fills_defaults() -> void:
	var s := StatusDef.from_dict("marked", {"effect": "damage_taken_percent"})
	assert_str(s.id).is_equal("marked")
	assert_str(s.display_name).is_equal("marked")
	assert_int(s.amount).is_equal(0)
	assert_int(s.max_stacks).is_equal(1)
	assert_str(s.expiry).is_equal(StatusDef.EXPIRY_HOLDER_NEXT_ACTION)
	assert_array(s.consumed_by).is_empty()
	assert_array(s.validate()).is_empty()


func test_table_lookups_and_comment_keys() -> void:
	var t := StatusTable.from_dict({"statuses": {"_c": "note", "exposed": {"name": "Exposed",
		"effect": "damage_taken_percent", "amount": 50}}})
	assert_array(t.ids()).contains_exactly(["exposed"])
	assert_bool(t.has("exposed")).is_true()
	assert_object(t.get_status("nope")).is_null()


func _problems(changes: Dictionary) -> Array[String]:
	var d := {"name": "Test", "effect": "damage_taken_percent", "amount": 10}
	d.merge(changes, true)
	return StatusDef.from_dict("test", d).validate()


func test_validate_rejects_bad_fields() -> void:
	assert_array(_problems({})).is_empty()
	assert_array(_problems({"effect": "explode"})).has_size(1)
	assert_array(_problems({"name": ""})).has_size(1)
	assert_array(_problems({"max_stacks": 0})).has_size(1)
	assert_array(_problems({"expiry": "someday"})).has_size(1)
	assert_array(_problems({"consumed_by": ["sneeze"]})).has_size(1)
	assert_array(_problems({"consumed_by": ["hit", "hit"]})).has_size(1)


func test_a_status_that_never_ends_is_rejected() -> void:
	assert_array(_problems({"expiry": "never"})).has_size(1)
	assert_array(_problems({"expiry": "never", "consumed_by": ["payoff"]})).is_empty()


func test_the_table_reports_every_bad_status() -> void:
	var t := StatusTable.from_dict({"statuses": {
		"a": {"name": "A", "effect": "nope"},
		"b": {"name": "B", "effect": "damage_taken_percent", "max_stacks": 0}}})
	assert_array(t.validate()).has_size(2)
