class_name StubSquadProvider
extends SquadProvider
## Four fake bots, the same every call, so the map can run before bot_data exists.
## The numbers are placeholders for tests, not tuning.


func get_squad() -> Array[SquadMemberSummary]:
	var squad: Array[SquadMemberSummary] = [
		SquadMemberSummary.new("stub_bolt", "Bolt", 30, 30, "aggressive", UnitStats.new(30, 8, 3, 7, 2, 10),
			_skills([["Strike", "damage_single"], ["Overcharge Shot", "damage_single_heavy"]])),
		SquadMemberSummary.new("stub_anvil", "Anvil", 45, 45, "defensive", UnitStats.new(45, 5, 8, 3, 4, 8),
			_skills([["Strike", "damage_single"], ["Brace", "guard_self"]])),
		SquadMemberSummary.new("stub_spark", "Spark", 22, 25, "supportive", UnitStats.new(25, 4, 3, 9, 5, 14),
			_skills([["Patch Up", "heal_single"], ["Shield Ally", "guard_ally"]])),
		SquadMemberSummary.new("stub_cog", "Cog", 35, 35, "methodical", UnitStats.new(35, 6, 5, 5, 3, 12),
			_skills([["Strike", "damage_single"], ["Arc Sweep", "damage_all"]])),
	]
	return squad


func _skills(pairs: Array) -> Array[Dictionary]:
	var skills: Array[Dictionary] = []
	for pair: Array in pairs:
		skills.append(SquadMemberSummary.make_skill(pair[0], pair[1]))
	return skills
