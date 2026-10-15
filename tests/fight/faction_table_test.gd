extends GdUnitTestSuite
## Enemy factions: which faction holds each region (data/combat/factions.json)
## and which enemies a fight there fields (FactionTable, EnemyTable.pick_for).
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const V := preload("res://tests/fight/variants/variant_test_helpers.gd")
const ACTS_PATH := "res://data/tuning/acts.json"

var _table: EnemyTable
var _factions: FactionTable


func before_test() -> void:
	_table = EnemyTable.load_default()
	_factions = _table.factions


static func _read(path: String) -> Dictionary:
	return JsonFile.read(path)


## Act id -> every region id of every map variant of the act.
static func _regions_by_act() -> Dictionary:
	var out := {}
	for act: Dictionary in _read(ACTS_PATH).acts:
		var ids: Array[String] = []
		for variant: Dictionary in act.variants:
			for region: Dictionary in _read(variant.region_file).regions:
				if not region.id in ids:
					ids.append(region.id)
		out[act.id] = ids
	return out


static func _squad() -> Array[SquadMemberSummary]:
	return StubSquadProvider.new().get_squad()


static func _enemy_ids(fight: Fight) -> Array[String]:
	var ids: Array[String] = []
	for c in fight.combatants:
		if c.side == Combatant.Side.ENEMY:
			ids.append(EnemyPersonalities.enemy_id_of(c.id))
	return ids


func test_the_shipped_tables_are_valid() -> void:
	assert_array(_table.validate(CombatTuning.load_default())).is_empty()


func test_every_region_of_every_act_variant_has_a_faction() -> void:
	var by_act := _regions_by_act()
	assert_int(by_act.size()).is_greater(0)
	for act: String in by_act:
		assert_bool(_factions.tier_by_act.has(act)).override_failure_message(act).is_true()
		for region: String in by_act[act]:
			var faction := _factions.faction_of(act, region)
			assert_bool(_factions.factions.has(faction)) \
				.override_failure_message("%s/%s has no faction" % [act, region]).is_true()
			assert_str(_factions.act_of(region)).is_equal(act)


func test_the_mixed_rule_gives_every_region_a_faction_too() -> void:
	var by_act := _regions_by_act()
	var seen := {}
	for act: String in by_act:
		for region: String in by_act[act]:
			var faction := _factions.faction_for_region(region, FightVariants.FACTIONS_MIXED)
			assert_array(_factions.mixed_pool).contains([faction])
			assert_str(_factions.faction_for_region(region, FightVariants.FACTIONS_MIXED)).is_equal(faction)
			seen[faction] = true
	assert_int(seen.size()).is_equal(_factions.mixed_pool.size())


func test_the_generic_rule_and_unknown_regions_have_no_faction() -> void:
	assert_str(_factions.faction_for_region("seattle", FightVariants.FACTIONS_GENERIC)).is_equal(FactionTable.GENERIC)
	assert_str(_factions.faction_for_region("test_territory")).is_equal(FactionTable.GENERIC)
	assert_str(_factions.faction_of("act2", "seattle")).is_equal(FactionTable.GENERIC)


func test_the_by_act_table_follows_the_design_default() -> void:
	# Act 1 human resistance; act 2 enhanced humans and the rival AI; act 3
	# aliens and the rival AI.
	var by_act := _regions_by_act()
	var expected := {
		"act1": ["human_resistance"],
		"act2": ["enhanced_humans", "rival_ai"],
		"act3": ["aliens", "rival_ai"],
	}
	for act: String in expected:
		var seen := {}
		for region: String in by_act[act]:
			seen[_factions.faction_of(act, region)] = true
		assert_array(seen.keys()).contains_exactly_in_any_order(expected[act])


func test_every_act_has_a_tier_per_defense_level_that_never_drops() -> void:
	for act: String in _factions.tier_by_act:
		var last := 0
		for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
			var index := _factions.tiers.find(_factions.tier_for(act, level))
			assert_int(index).override_failure_message("%s level %d" % [act, level]).is_greater_equal(last)
			last = index
	assert_str(_factions.tier_for("act1", 0)).is_equal("beginner")
	assert_str(_factions.tier_for("act3", 5)).is_equal("advanced")


func test_a_unit_type_joins_the_pool_at_its_level() -> void:
	for faction: String in _factions.factions:
		for u: Dictionary in _factions.factions[faction].units:
			var id := FactionTable.enemy_id(u.unit, "medium")
			for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
				assert_bool(id in _factions.pool(faction, level, "medium")) \
					.override_failure_message("%s level %d" % [id, level]).is_equal(level >= int(u.from_level))


func test_a_faction_fight_fields_the_region_faction_at_the_act_tier() -> void:
	var cases := [["bellevue", 3, "human_resistance", "act1"], ["illinois", 2, "enhanced_humans", "act2"],
		["california", 4, "rival_ai", "act2"], ["china", 1, "aliens", "act3"]]
	for spec: Array in cases:
		var request := FightRequest.new(FightRequest.Kind.ATTACK, spec[0], spec[1], _squad())
		var ids := _enemy_ids(Fight.new(request, 5))
		assert_int(ids.size()).is_equal(int(_table.levels[spec[1]].count))
		for id in ids:
			var e: Dictionary = _table.enemies[id]
			assert_str(e.faction).override_failure_message(id).is_equal(spec[2])
			assert_str(e.tier).override_failure_message(id).is_equal(_factions.tier_for(spec[3], spec[1]))


func test_generic_switch_and_unknown_territories_keep_today_enemies() -> void:
	var generic := V.tuning_with(FightVariants.ENEMY_FACTIONS, FightVariants.FACTIONS_GENERIC)
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		var pool: Array = _table.levels[level].pool
		for territory in ["seattle", "test_territory"]:
			var request := FightRequest.new(FightRequest.Kind.ATTACK, territory, level, _squad())
			var tuning := generic if territory == "seattle" else CombatTuning.load_default()
			for id in _enemy_ids(Fight.new(request, 9, tuning)):
				assert_array(pool).contains([id])


func test_the_mixed_switch_fields_the_mixed_faction() -> void:
	var mixed := V.tuning_with(FightVariants.ENEMY_FACTIONS, FightVariants.FACTIONS_MIXED)
	for region in ["seattle", "texas", "japan"]:
		var faction := _factions.faction_for_region(region, FightVariants.FACTIONS_MIXED)
		var request := FightRequest.new(FightRequest.Kind.ATTACK, region, 2, _squad())
		for id in _enemy_ids(Fight.new(request, 3, mixed)):
			assert_str(_table.enemies[id].faction).is_equal(faction)


func test_seeded_faction_fights_replay_exactly() -> void:
	for option: String in FightVariants.KNOWN[FightVariants.ENEMY_FACTIONS]:
		var tuning := V.tuning_with(FightVariants.ENEMY_FACTIONS, option)
		for region in ["seattle", "michigan", "california", "india"]:
			for s in [1, 2, 3]:
				var request := FightRequest.new(FightRequest.Kind.ATTACK, region, 3, _squad())
				var a := HeadlessFightRunner.run(request, s, PatientFightPolicy.new(), IntentFightPolicy.new(), tuning).log_text()
				var b := HeadlessFightRunner.run(request, s, PatientFightPolicy.new(), IntentFightPolicy.new(), tuning).log_text()
				assert_str(a).override_failure_message("%s %s seed %d" % [option, region, s]).is_equal(b)


func test_the_seed_changes_the_draw_within_a_faction() -> void:
	var draws := {}
	for s in 20:
		var request := FightRequest.new(FightRequest.Kind.ATTACK, "california", 4, _squad())
		draws[str(_enemy_ids(Fight.new(request, s)))] = true
	assert_int(draws.size()).is_greater(1)


func test_validate_reports_a_broken_table() -> void:
	var broken := FactionTable.from_dict({
		"factions": {"x": {"units": [{"unit": "missing", "from_level": 0}]}},
		"tiers": ["beginner"],
		"tier_by_act": {"a": ["beginner"]},
		"mixed_pool": ["y"],
		"regions": {"a": {"x": ["r1"], "z": ["r1"]}},
	})
	var problems := broken.validate(_table)
	assert_int(problems.size()).is_greater_equal(4)
	assert_str("\n".join(problems)).contains("no enemy missing_beginner").contains("listed more than once") \
		.contains("unknown faction z").contains("mixed_pool")


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

