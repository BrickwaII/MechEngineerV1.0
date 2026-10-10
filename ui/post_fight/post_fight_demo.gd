extends Control
## Demo entry for the readout: plays one canned fight (fixed seed, fixed
## policy, three hand-made bots of generations 1 to 3), applies PostFight and
## shows the report. Some uses are pre-banked so level-ups appear.

const Readout := preload("res://ui/post_fight/post_fight_readout.gd")

const DEMO_SEED := 12
const DEMO_DEFENSE_LEVEL := 2

var readout: Control
var report: PostFightReport
var bots: Array[Bot] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	readout = Readout.new()
	add_child(readout)
	report = build_canned_report()
	readout.show_report(report)


func build_canned_report() -> PostFightReport:
	bots = [
		_bot("bolt", "Bolt", 1, UnitStats.new(40, 8, 4, 7, 2, 12), [-0.3, 0.0, 0.0]),
		_bot("anvil", "Anvil", 2, UnitStats.new(45, 6, 7, 4, 3, 9), [0.4, 0.2, 0.0]),
		_bot("spark", "Spark", 3, UnitStats.new(30, 7, 3, 9, 1, 14), [0.0, -0.2, 0.5]),
	]
	var squad: Array[SquadMemberSummary] = []
	for b in bots:
		squad.append(b.to_summary())
	var request := FightRequest.new(FightRequest.Kind.ATTACK, "demo", DEMO_DEFENSE_LEVEL, squad)
	var fight := HeadlessFightRunner.run(request, DEMO_SEED, RandomFightPolicy.new())
	var ledger := SkillUseLedger.new()
	for b in bots:
		ledger.set_banked(b.id, "Strike", 4)
	return PostFight.apply(fight, bots, ledger)


static func _bot(id: String, name: String, generation: int, stats: UnitStats, scales: Array) -> Bot:
	var skills: Array[Skill] = [
		Skill.new("Strike", "damage_single", 0, 1),
		Skill.new("Overcharge Shot", "damage_single_heavy", 4, 1),
	]
	return Bot.new(id, name, stats, Personality.new(generation, scales[0], scales[1], scales[2]), skills)
