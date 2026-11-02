extends GdUnitTestSuite
## Action definitions (the plan's ActionDef, here CombatSkill) load from
## data/combat/actions.json, validate, and kept every number they had in
## combat_tuning.json before the combat rework (S1).


## The skill table as combat_tuning.json held it before S1:
## id -> [name, energy_cost, power_percent, effect, target].
const PRE_REWORK := {
	"strike": ["Strike", 0, 100, "damage", "opponent"],
	"heavy_strike": ["Heavy Strike", 4, 150, "damage", "opponent"],
	"overload": ["Overload", 9, 220, "damage", "opponent"],
	"repair": ["Repair", 2, 100, "heal", "ally"],
	"arc_sweep": ["Arc Sweep", 6, 60, "damage", "all_opponents"],
	"brace": ["Brace", 2, 50, "guard", "self"],
	"patch_up": ["Patch Up", 3, 100, "heal", "ally"],
	"shield": ["Shield Ally", 3, 40, "guard", "ally"],
}


## Recovery given to the migrated actions on purpose (S2), in percent of a turn.
const RECOVERY := {"heavy_strike": 30, "overload": 50, "arc_sweep": 20}


func _rework_fields_are_defaults(a: CombatSkill) -> void:
	assert_int(a.recovery).is_equal(RECOVERY.get(a.id, 0))
	assert_int(a.hit_count).is_equal(1)
	assert_str(a.damage_type).is_empty()
	assert_array(a.tags).is_empty()
	assert_str(a.applies_status).is_empty()
	assert_str(a.payoff_condition).is_empty()
	assert_int(a.payoff_bonus_percent).is_equal(0)


func _full() -> CombatSkill:
	return CombatSkill.from_dict("shred", {
		"name": "Shred", "energy_cost": 2, "power_percent": 30, "recovery": 15, "hit_count": 3,
		"damage_type": "kinetic", "tags": ["setup", "offense"], "applies_status": "exposed",
		"payoff_condition": "exposed", "payoff_bonus_percent": 50})


func test_the_shipped_actions_load_and_validate() -> void:
	var table := ActionTable.load_default()
	assert_object(table).is_not_null()
	assert_array(table.validate()).is_empty()


func test_every_pre_rework_skill_migrated_with_the_same_numbers() -> void:
	var table := ActionTable.load_default()
	assert_array(table.actions.keys()).contains_exactly_in_any_order(PRE_REWORK.keys())
	for id: String in PRE_REWORK:
		var want: Array = PRE_REWORK[id]
		var a: CombatSkill = table.actions[id]
		assert_str(a.id).is_equal(id)
		assert_str(a.display_name).is_equal(want[0])
		assert_int(a.energy_cost).is_equal(want[1])
		assert_int(a.power_percent).is_equal(want[2])
		assert_str(a.effect).is_equal(want[3])
		assert_str(a.target).is_equal(want[4])
		assert_int(a.level).is_equal(1)
		_rework_fields_are_defaults(a)


func test_combat_tuning_reads_its_skills_from_the_action_table() -> void:
	var tuning := CombatTuning.load_default()
	var table := ActionTable.load_default()
	assert_array(tuning.skills.keys()).is_equal(table.actions.keys())
	assert_bool(tuning.skills.has("strike")).is_true()
	assert_object(tuning.skill("overload")).is_not_null()


func test_the_tuning_file_no_longer_holds_a_skill_table() -> void:
	var d: Dictionary = JsonFile.read(CombatTuning.DEFAULT_PATH)
	assert_bool(d.has("skills")).is_false()


func test_each_tuning_holds_its_own_actions() -> void:
	var a := CombatTuning.load_default()
	var b := CombatTuning.load_default()
	a.skills["strike"].power_percent = 999
	a.skills["new"] = CombatSkill.new("new", "New")
	assert_int(b.skills["strike"].power_percent).is_equal(100)
	assert_bool(b.skills.has("new")).is_false()


func test_from_dict_reads_every_rework_field() -> void:
	var a := _full()
	assert_int(a.recovery).is_equal(15)
	assert_int(a.hit_count).is_equal(3)
	assert_str(a.damage_type).is_equal("kinetic")
	assert_array(a.tags).contains_exactly(["setup", "offense"])
	assert_str(a.applies_status).is_equal("exposed")
	assert_str(a.payoff_condition).is_equal("exposed")
	assert_int(a.payoff_bonus_percent).is_equal(50)
	assert_bool(a.has_payoff()).is_true()
	assert_array(a.validate(["exposed"])).is_empty()


func test_from_dict_defaults_match_the_constructor() -> void:
	var a := CombatSkill.from_dict("mend", {"name": "Mend", "energy_cost": 1, "power_percent": 80, "effect": "heal"})
	assert_str(a.target).is_equal(CombatSkill.TARGET_ALLY)
	_rework_fields_are_defaults(a)
	assert_bool(a.has_payoff()).is_false()


func test_a_level_or_rank_copy_keeps_every_rework_field() -> void:
	var a := _full()
	var leveled := a.at_level(3, "Big Shred", 10, 80)
	var ranked := SkillRanks.load_default().apply(a, 7, "", 80)
	for c: CombatSkill in [leveled, ranked, a.copy_definition()]:
		assert_int(c.recovery).is_equal(15)
		assert_int(c.hit_count).is_equal(3)
		assert_str(c.damage_type).is_equal("kinetic")
		assert_array(c.tags).contains_exactly(["setup", "offense"])
		assert_str(c.applies_status).is_equal("exposed")
		assert_str(c.payoff_condition).is_equal("exposed")
		assert_int(c.payoff_bonus_percent).is_equal(50)


func test_a_copy_owns_its_tags() -> void:
	var a := _full()
	var c := a.copy_definition()
	c.tags.append("payoff")
	assert_array(a.tags).has_size(2)


func test_copy_definition_drops_rank_state() -> void:
	var ranked := SkillRanks.load_default().apply(ActionTable.load_default().actions["strike"], 13, "", 80)
	assert_int(ranked.pierce_percent).is_greater(0)
	var c := ranked.copy_definition()
	assert_int(c.level).is_equal(1)
	assert_int(c.pierce_percent).is_equal(0)
	assert_bool(c.names_rank).is_false()


func _problems(changes: Dictionary, status_ids: Variant = ["exposed"]) -> Array[String]:
	var d := {"name": "Test", "energy_cost": 1, "power_percent": 100}
	d.merge(changes, true)
	return CombatSkill.from_dict("test", d).validate(status_ids)


func test_validate_accepts_a_plain_action() -> void:
	assert_array(_problems({})).is_empty()


func test_validate_rejects_bad_rework_fields() -> void:
	assert_array(_problems({"recovery": -1})).has_size(1)
	assert_array(_problems({"hit_count": 0})).has_size(1)
	assert_array(_problems({"hit_count": 2, "effect": "heal"})).has_size(1)
	assert_array(_problems({"damage_type": "fire", "effect": "guard"})).has_size(1)
	assert_array(_problems({"tags": ["setup", "setup"]})).has_size(1)
	assert_array(_problems({"tags": [""]})).has_size(1)
	assert_array(_problems({"applies_status": "nope"})).has_size(1)
	assert_array(_problems({"payoff_condition": "exposed"})).has_size(1)
	assert_array(_problems({"payoff_bonus_percent": 50})).has_size(1)
	assert_array(_problems({"payoff_condition": "nope", "payoff_bonus_percent": 50})).has_size(1)
	assert_array(_problems({"payoff_condition": "exposed", "payoff_bonus_percent": 50, "effect": "heal"})).has_size(1)


func test_validate_rejects_bad_basic_fields() -> void:
	assert_array(_problems({"effect": "explode"})).has_size(1)
	assert_array(_problems({"target": "everyone"})).has_size(1)
	assert_array(_problems({"effect": "heal", "target": "opponent"})).has_size(1)
	assert_array(_problems({"energy_cost": -1})).has_size(1)
	assert_array(_problems({"power_percent": -5})).has_size(1)


func test_validate_skips_status_names_without_a_status_list() -> void:
	assert_array(_problems({"applies_status": "nope"}, null)).is_empty()


func test_the_table_checks_status_names_against_the_status_table() -> void:
	var table := ActionTable.from_dict({"actions": {
		"shred": {"name": "Shred", "energy_cost": 2, "power_percent": 30, "applies_status": "jammed"}}})
	assert_array(table.validate(StatusTable.load_default())).has_size(1)
	var statuses := StatusTable.from_dict({"statuses": {"jammed": {"name": "Jammed",
		"effect": StatusDef.EFFECT_DAMAGE_TAKEN_PERCENT, "amount": 10}}})
	assert_array(table.validate(statuses)).is_empty()


func test_an_empty_table_is_reported_and_comments_are_skipped() -> void:
	var table := ActionTable.from_dict({"_comment": "x", "actions": {"_note": "y"}})
	assert_array(table.actions.keys()).is_empty()
	assert_array(table.validate()).has_size(1)


func test_combat_tuning_validate_reports_a_broken_action() -> void:
	var tuning := CombatTuning.load_default()
	tuning.skills["strike"].hit_count = 0
	tuning.skills["overload"].applies_status = "nope"
	assert_array(tuning.validate()).has_size(2)
