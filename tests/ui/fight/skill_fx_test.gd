extends GdUnitTestSuite
## Every skill's look and sound, and how they grow with the skill's level.

const CATALOG := ["Strike", "Overcharge Shot", "Arc Sweep", "Brace", "Patch Up", "Shield Ally",
	"Heavy Strike", "Overload", "Repair"]


func _skill(id: String, name := "", level := 1) -> CombatSkill:
	var tuning := CombatTuning.load_default()
	return tuning.skill(id).at_level(level, name, tuning.power_percent_per_level, tuning.max_guard_percent)


func test_every_skill_in_the_catalog_has_its_own_look_and_sound() -> void:
	var sounds := {}
	for name: String in CATALOG:
		var fx := SkillFx.spec(SkillFx.slug(name))
		assert_dict(fx).override_failure_message(name).is_not_empty()
		assert_str(str(fx.motion)).override_failure_message(name).is_not_empty()
		assert_array(SkillFx.MOTIONS).contains([fx.motion])
		assert_bool(SoundPlayer.sound_def(StringName(fx.sound)).is_empty()).override_failure_message(name).is_false()
		assert_bool(sounds.has(fx.sound)).override_failure_message("%s shares a sound" % name).is_false()
		sounds[fx.sound] = true
		for key in ["charge_effect", "projectile", "impact_effect"]:
			if not str(fx[key]).is_empty():
				assert_object(BattleArt.effect_frames(fx[key])).override_failure_message("%s %s" % [name, key]).is_not_null()


func test_bot_skills_from_skills_json_all_have_a_look() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/bot_data/skills.json"))
	for entry: Dictionary in catalog.skills:
		assert_dict(SkillFx.spec(SkillFx.slug(entry.name))).override_failure_message(entry.name).is_not_empty()


func test_a_skill_looks_like_its_own_name_then_its_id_then_its_effect() -> void:
	assert_str(SkillFx.fx_id_for(_skill("heavy_strike", "Overcharge Shot"))).is_equal("overcharge_shot")
	assert_str(SkillFx.fx_id_for(_skill("heavy_strike"))).is_equal("heavy_strike")
	assert_str(SkillFx.fx_id_for(_skill("shield", "Bubble"))).is_equal("shield_ally")
	var odd := CombatSkill.new("mystery", "Mystery", 1, 100, CombatSkill.EFFECT_HEAL)
	assert_str(SkillFx.fx_id_for(odd)).is_equal("repair")


func test_each_level_steps_up_until_the_max() -> void:
	assert_int(SkillFx.max_level()).is_equal(PostFightTuning.load_default().max_level)
	for level in range(2, SkillFx.max_level() + 1):
		var low := SkillFx.step(level - 1)
		var high := SkillFx.step(level)
		assert_float(float(high.scale)).override_failure_message("scale %d" % level).is_greater(float(low.scale))
		assert_float(float(high.brightness)).override_failure_message("brightness %d" % level).is_greater(float(low.brightness))
		assert_int(int(high.particles)).override_failure_message("particles %d" % level).is_greater(int(low.particles))
		assert_int(int(high.extra)).is_greater_equal(int(low.extra))
		assert_int(high.layers.size()).is_greater_equal(low.layers.size())
	assert_dict(SkillFx.step(SkillFx.max_level() + 5)).is_equal(SkillFx.step(SkillFx.max_level()))


func test_a_maxed_skill_is_fuller_and_heavier_but_not_longer() -> void:
	var settings := GameSettings.new()
	var fight := Fight.new(FightRequest.new(FightRequest.Kind.ATTACK, "t", 1, StubSquadProvider.new().get_squad()), 1)
	for id in ["heavy_strike", "overload", "arc_sweep"]:
		var e := FightEvent.new(FightEvent.Kind.SKILL, 1, "x", "", id)
		var low := BattleBeat.from_events(fight, [e], settings)
		low.fx = SkillFx.for_skill(_skill(id, "", 1))
		var high := BattleBeat.from_events(fight, [e], settings)
		high.fx = SkillFx.for_skill(_skill(id, "", SkillFx.max_level()))
		assert_float(high.duration()).is_equal(low.duration())
		assert_int(SkillFx.sounds(high.fx).size()).is_greater(SkillFx.sounds(low.fx).size())
		assert_int(int(high.fx.particles)).is_greater(int(low.fx.particles))
		assert_str(SkillFx.impact_kind(high.fx, false)).is_equal("heavy")
		assert_str(SkillFx.impact_kind(low.fx, false)).is_equal("light")
	var shot_low := SkillFx.for_skill(_skill("heavy_strike", "Overcharge Shot", 1))
	var shot_max := SkillFx.for_skill(_skill("heavy_strike", "Overcharge Shot", SkillFx.max_level()))
	assert_int(shot_low.projectiles).is_equal(1)
	assert_int(shot_max.projectiles).is_greater(1)
	assert_int(SkillFx.for_skill(_skill("strike")).projectiles).is_equal(0)


func test_an_attack_beat_stays_inside_the_attack_rule() -> void:
	var settings := GameSettings.new()
	var e := FightEvent.new(FightEvent.Kind.SKILL, 1, "x", "", "strike")
	var beat := BattleBeat.from_events(null, [e], settings)
	var ms := beat.duration() * 1000.0
	assert_float(ms).is_between(FeelData.number("attack.min_ms"), FeelData.number("attack.max_ms"))
	assert_float(beat.impact_at()).is_less(beat.duration())


func test_big_hits_are_a_share_of_max_hp_or_a_down() -> void:
	var share := BattleArt.number("big_hit_share")
	assert_bool(SkillFx.is_big_hit(int(ceil(40 * share)), 40, false)).is_true()
	assert_bool(SkillFx.is_big_hit(1, 40, false)).is_false()
	assert_bool(SkillFx.is_big_hit(1, 40, true)).is_true()


func test_layer_sounds_exist_and_are_throttled() -> void:
	for step: Dictionary in BattleArt.data().level_steps:
		for layer: String in step.layers:
			var def := SoundPlayer.sound_def(StringName(layer))
			assert_dict(def).override_failure_message(layer).is_not_empty()
			assert_int(int(def.throttle.max)).is_equal(1)
