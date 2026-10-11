class_name OddsCalibration
extends RefCounted
## Checks that the simulated odds labels mean what they say: for drafted
## squads against act regions at every defense level, each estimate's label
## (OddsEstimator) next to the outcome of the real auto-fight, played with the
## seed the run would use (AutoFightService.seed_for(), never one of the
## estimate's own seeds). A calibrated label wins about as often as its band
## says.
##
##   godot --headless --path . -s res://tools/odds_calibration_cli.gd -- --squads 10 --regions 4
##
## Squad i is drafted from seed base_seed + i (BotFactory, the default
## draft). Every switch stays at its default.


## One estimate and the real fight's outcome.
class Sample:
	var act := ""
	var region := ""
	var level := 0
	var label := ""
	var percent := 0
	var won := false


var samples: Array[Sample] = []
var labels: Array[String] = []
var msec_total := 0
var msec_max := 0


static func run(squads: int, regions_per_act: int, base_seed := 1, estimator: OddsEstimator = null) -> OddsCalibration:
	var c := OddsCalibration.new()
	if estimator == null:
		estimator = OddsEstimator.new()
	for band in estimator.tuning.bands:
		c.labels.append(band["label"])
	var factions := FactionTable.load_default()
	var auto := AutoFightService.new(estimator.combat_tuning, estimator.enemy_table)
	var factory := BotFactory.new(BotTuning.load_default())
	var acts: Array = factions.regions_by_act.keys()
	acts.sort()
	for i in squads:
		var squad: Array[SquadMemberSummary] = []
		for bot in factory.build_squad(base_seed + i).get_fielded():
			squad.append(bot.to_summary())
		for act: String in acts:
			var regions: Array = (factions.regions_by_act[act] as Dictionary).keys()
			regions.sort()
			for r in mini(regions_per_act, regions.size()):
				var region: String = regions[r]
				for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
					var e := estimator.estimate(squad, region, level, base_seed + i)
					c.msec_total += e.msec
					c.msec_max = maxi(c.msec_max, e.msec)
					var s := Sample.new()
					s.act = act
					s.region = region
					s.level = level
					s.label = e.label
					s.percent = e.percent()
					s.won = auto.resolve(FightRequest.new(FightRequest.Kind.ATTACK, region, level, squad)).is_victory()
					c.samples.append(s)
	return c


## Real wins and fights for samples with `label` (and `level`, unless -1).
func tally(label: String, level := -1) -> Vector2i:
	var t := Vector2i.ZERO
	for s in samples:
		if s.label == label and (level < 0 or s.level == level):
			t.y += 1
			if s.won:
				t.x += 1
	return t


## Mean estimated percent of samples with `label`.
func mean_estimate(label: String) -> float:
	var total := 0
	var n := 0
	for s in samples:
		if s.label == label:
			total += s.percent
			n += 1
	return float(total) / n if n > 0 else 0.0


## A markdown table: one row per defense level, one column per label, each
## cell the real auto-fight win rate (wins/fights); then the totals.
func format_markdown() -> String:
	var lines := PackedStringArray()
	var head := "| Defense level |"
	var rule := "|---|"
	for label in labels:
		head += " %s |" % label
		rule += "---|"
	lines.append(head)
	lines.append(rule)
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		var line := "| %d |" % level
		for label in labels:
			line += " %s |" % _cell(tally(label, level))
		lines.append(line)
	var all := "| **All** |"
	for label in labels:
		all += " **%s** |" % _cell(tally(label))
	lines.append(all)
	var est := "| Mean estimate |"
	for label in labels:
		est += " %.0f%% |" % mean_estimate(label)
	lines.append(est)
	return "\n".join(lines)


static func _cell(t: Vector2i) -> String:
	if t.y == 0:
		return "–"
	return "%.0f%% (%d/%d)" % [100.0 * t.x / t.y, t.x, t.y]
