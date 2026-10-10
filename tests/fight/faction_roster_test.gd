extends GdUnitTestSuite
## The enemy roster (data/combat/enemy_tables.json): every entry draws from
## the sprite manifest, uses known skills and has a personality.

var _table: EnemyTable


func before_test() -> void:
	_table = EnemyTable.load_default()


func test_every_enemy_has_a_manifest_sprite_in_its_tier() -> void:
	for id: String in _table.enemies:
		var look := _table.sprite_of(id)
		assert_dict(look).override_failure_message("%s names no sprite" % id).is_not_empty()
		var unit := SpriteManifest.unit(look.unit)
		assert_str(unit.get("kind", "")).override_failure_message("%s: %s" % [id, look.unit]).is_equal("enemy")
		var sheet := SpriteManifest.sheet_for(look.unit, look.tier)
		assert_bool(ResourceLoader.exists(sheet)).override_failure_message("%s: %s" % [id, sheet]).is_true()


func test_every_faction_enemy_draws_in_its_own_tier_and_faction() -> void:
	for id: String in _table.enemies:
		var e: Dictionary = _table.enemies[id]
		if not e.has("faction"):
			continue
		assert_str(id).is_equal(FactionTable.enemy_id(e.unit, e.tier))
		assert_str(e.tier).is_equal(_table.sprite_of(id).tier)
		assert_str(SpriteManifest.unit(e.sprite).get("faction", "")).override_failure_message(id).is_equal(e.faction)


func test_every_unit_type_comes_in_every_tier() -> void:
	for faction: String in _table.factions.factions:
		for u: Dictionary in _table.factions.factions[faction].units:
			for tier: String in SpriteManifest.tiers():
				assert_bool(_table.enemies.has(FactionTable.enemy_id(u.unit, tier))) \
					.override_failure_message("%s %s" % [u.unit, tier]).is_true()


func test_every_enemy_skill_exists() -> void:
	var tuning := CombatTuning.load_default()
	for id: String in _table.enemies:
		assert_array(_table.skills_of(id)).override_failure_message(id).is_not_empty()
		for s in _table.skills_of(id):
			assert_object(tuning.skill(s)).override_failure_message("%s: %s" % [id, s]).is_not_null()


func test_every_enemy_has_a_personality() -> void:
	assert_array(EnemyPersonalities.load_default().missing_from(_table)).is_empty()


func test_tiers_get_stronger_and_keep_their_skills() -> void:
	for faction: String in _table.factions.factions:
		for u: Dictionary in _table.factions.factions[faction].units:
			var previous: Dictionary = {}
			for tier: String in SpriteManifest.tiers():
				var e: Dictionary = _table.enemies[FactionTable.enemy_id(u.unit, tier)]
				if not previous.is_empty():
					assert_int(int(e.hp)).override_failure_message(e.name).is_greater(int(previous.hp))
					assert_int(int(e.attack)).override_failure_message(e.name).is_greater_equal(int(previous.attack))
					assert_int(e.skills.size()).override_failure_message(e.name).is_greater_equal(previous.skills.size())
				previous = e


func test_the_manifest_maps_combatant_ids_to_sprites() -> void:
	assert_dict(SpriteManifest.for_enemy("resistance_soldier_medium#2")) \
		.is_equal({"unit": "resistance_soldier", "tier": "medium"})
	assert_dict(SpriteManifest.for_enemy("scrap_drone")).is_equal({"unit": "enemy_drone", "tier": "beginner"})
	assert_dict(SpriteManifest.for_enemy("nobody#1")).is_empty()


func test_each_faction_has_an_icon() -> void:
	for faction: String in _table.factions.factions:
		assert_bool(ResourceLoader.exists(_table.factions.faction_icon(faction))).override_failure_message(faction).is_true()
	assert_str(_table.factions.faction_icon(FactionTable.GENERIC)).is_empty()


func test_each_faction_has_its_own_color() -> void:
	var colors := {}
	for faction: String in _table.factions.factions:
		colors[_table.factions.faction_color(faction).to_html()] = faction
	assert_int(colors.size()).is_equal(_table.factions.factions.size())
