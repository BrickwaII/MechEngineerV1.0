extends RefCounted
## Builders shared by the fight tests.


static func stats(hp: int, attack: int, defense: int, speed: int, battery: int, elasticity := 0) -> UnitStats:
	return UnitStats.new(hp, attack, defense, speed, elasticity, battery)


static func member(id: String, s: UnitStats, hp := -1) -> SquadMemberSummary:
	var current := s.hp if hp < 0 else hp
	return SquadMemberSummary.new(id, id.capitalize(), current, s.hp, "test", s)


## Copies of `squad` with their skills dropped, so each member fights with
## CombatTuning.player_skills. For tests of fight mechanics that predate bot
## skills; tests of bot skills use the summaries' own skills.
static func without_skills(squad: Array[SquadMemberSummary]) -> Array[SquadMemberSummary]:
	var out: Array[SquadMemberSummary] = []
	for m in squad:
		var copy: SquadMemberSummary = m.duplicate()
		copy.skills = []
		out.append(copy)
	return out


static func request(squad: Array[SquadMemberSummary], level := 0) -> FightRequest:
	return FightRequest.new(FightRequest.Kind.ATTACK, "test_territory", level, squad)


## An enemy table whose every level fields `count` copies of `enemy_id`.
static func table(enemy_defs: Dictionary, enemy_id: String, count := 1) -> EnemyTable:
	var levels := []
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		levels.append({"level": level, "count": count, "pool": [enemy_id], "rewards": {"energy": 3, "material": 1}})
	return EnemyTable.from_dict({"enemies": enemy_defs, "levels": levels})


static func enemy_def(name: String, s: UnitStats, skills: Array = ["strike"]) -> Dictionary:
	return {
		"name": name, "hp": s.hp, "attack": s.attack, "defense": s.defense, "speed": s.speed,
		"elasticity": s.elasticity, "battery_capacity": s.battery_capacity, "skills": skills,
	}


## A fight of one ally against one enemy, both with every player skill.
static func duel(ally: UnitStats, foe: UnitStats, tuning: CombatTuning = null) -> Fight:
	tuning = tuning if tuning != null else CombatTuning.load_default()
	var skills: Array = []
	skills.assign(tuning.player_skills)
	var t := table({"foe": enemy_def("Foe", foe, skills)}, "foe")
	var squad: Array[SquadMemberSummary] = [member("ally", ally)]
	return Fight.new(request(squad), 1, tuning, t)

