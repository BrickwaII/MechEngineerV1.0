extends GdUnitTestSuite
## StatusManager applies, stacks, consumes and expires statuses on units
## (combat rework S3). Unit-level: no fight runs here; see
## exposed_combo_test.gd for the same rules inside fights.

const H := preload("res://tests/fight/fight_test_helpers.gd")

var _tuning: CombatTuning
var _manager: StatusManager


func before_test() -> void:
	_tuning = CombatTuning.load_default()
	_manager = StatusManager.new(StatusTable.from_dict({"statuses": {
		"exposed": {"name": "Exposed", "effect": "damage_taken_percent", "amount": 50, "expiry": "holder_next_action", "consumed_by": ["hit"]},
		"marked": {"name": "Marked", "effect": "damage_taken_percent", "amount": 10, "max_stacks": 3, "expiry": "never", "consumed_by": ["payoff"]},
	}}))


func _unit(id := "u") -> Combatant:
	var no_skills: Array[String] = []
	return Combatant.new(id, id, Combatant.Side.ENEMY, 0, H.stats(50, 5, 5, 5, 5), 50, no_skills, _tuning)


func _payoff_on(status_id: String) -> CombatSkill:
	var s := CombatSkill.new("finisher", "Finisher", 4, 150)
	s.payoff_condition = status_id
	s.payoff_bonus_percent = 50
	return s


func test_apply_puts_the_status_on_with_its_source() -> void:
	var u := _unit()
	var held := _manager.apply(u, "exposed", "bolt", 7)
	assert_object(held).is_not_null()
	assert_array(u.status_ids()).is_equal(["exposed"])
	assert_int(held.stacks).is_equal(1)
	assert_str(held.source_id).is_equal("bolt")
	assert_int(held.applied_action).is_equal(7)


func test_applying_at_max_stacks_only_refreshes() -> void:
	var u := _unit()
	_manager.apply(u, "exposed", "a", 1)
	var held := _manager.apply(u, "exposed", "b", 2)
	assert_int(u.statuses.size()).is_equal(1)
	assert_int(held.stacks).is_equal(1)
	assert_str(held.source_id).is_equal("b")
	assert_int(held.applied_action).is_equal(2)


func test_stacks_add_up_to_the_cap() -> void:
	var u := _unit()
	for i in 5:
		_manager.apply(u, "marked")
	assert_int(u.status("marked").stacks).is_equal(3)
	assert_int(_manager.damage_taken_percent(u)).is_equal(30)


func test_unknown_status_or_downed_unit_gets_nothing() -> void:
	var u := _unit()
	assert_object(_manager.apply(u, "nope")).is_null()
	u.hp = 0
	assert_object(_manager.apply(u, "exposed")).is_null()
	assert_array(u.statuses).is_empty()


func test_damage_taken_percent_sums_every_status() -> void:
	var u := _unit()
	assert_int(_manager.damage_taken_percent(u)).is_equal(0)
	_manager.apply(u, "exposed")
	_manager.apply(u, "marked")
	assert_int(_manager.damage_taken_percent(u)).is_equal(60)


func test_on_unit_acts_ends_only_holder_next_action_statuses() -> void:
	var u := _unit()
	_manager.apply(u, "exposed")
	_manager.apply(u, "marked")
	var gone := _manager.on_unit_acts(u)
	assert_array(gone.map(func(s: StatusInstance) -> String: return s.status_id)).is_equal(["exposed"])
	assert_array(u.status_ids()).is_equal(["marked"])
	assert_array(_manager.on_unit_acts(u)).is_empty()


func test_a_hit_uses_up_hit_consumed_statuses_only() -> void:
	var u := _unit()
	_manager.apply(u, "exposed")
	_manager.apply(u, "marked")
	var gone := _manager.consume_after_hit(u, CombatSkill.new("strike", "Strike", 0, 100))
	assert_array(gone.map(func(s: StatusInstance) -> String: return s.status_id)).is_equal(["exposed"])
	assert_array(u.status_ids()).is_equal(["marked"])


func test_a_payoff_uses_up_the_status_it_names() -> void:
	var u := _unit()
	_manager.apply(u, "marked")
	assert_array(_manager.consume_after_hit(u, _payoff_on("exposed"))).is_empty()
	assert_bool(u.has_status("marked")).is_true()
	var gone := _manager.consume_after_hit(u, _payoff_on("marked"))
	assert_int(gone.size()).is_equal(1)
	assert_bool(u.has_status("marked")).is_false()


func test_clone_for_preview_copies_statuses_deeply() -> void:
	var u := _unit()
	_manager.apply(u, "marked")
	var c := u.clone_for_preview()
	assert_array(c.status_ids()).is_equal(["marked"])
	_manager.apply(c, "marked")
	_manager.apply(c, "exposed")
	assert_int(u.status("marked").stacks).is_equal(1)
	assert_bool(u.has_status("exposed")).is_false()


func test_the_shipped_tuning_holds_the_shipped_statuses() -> void:
	assert_bool(_tuning.statuses.has("exposed")).is_true()
	assert_bool(StatusManager.new(_tuning.statuses).table.has("exposed")).is_true()
