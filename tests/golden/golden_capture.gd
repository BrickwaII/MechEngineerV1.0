extends SceneTree
## Golden outputs: writes fixed-seed results of every deterministic system to
## a folder, as plain text, so two builds can be compared with `diff -r`.
## Used to show a refactor changes no behaviour (scripts/golden_check.sh).
##
##   godot --headless --path . -s res://tests/golden/golden_capture.gd -- OUT_DIR [--quick]
##
## Covered: fights (every policy, kind, level and fight-variant option, with
## logs, tags, events, previews and post-fight growth), odds estimates, the
## dev tools' reports (batch sim, variant and campaign comparisons, faction
## win rates, balance curve, loss report, odds calibration), campaign
## autoplay records and end states, save files, region maps, map tunings, the
## act plan, and whole runs played through RunFlow: their journals (wall-clock
## fields stripped), timelines, replays, summaries and save files.
## Wall-clock values (ts, unix, play_s, seconds, msec) are left out.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const VOLATILE_KEYS := ["ts", "unix", "play_s", "seconds", "msec", "msec_total", "msec_max", "created", "updated_unix"]

var out_dir := ""
var quick := false
## Per capture, so two captures can run side by side.
var runs_root := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--quick":
			quick = true
		elif out_dir.is_empty():
			out_dir = a
	if out_dir.is_empty():
		printerr("usage: -s res://tests/golden/golden_capture.gd -- OUT_DIR [--quick]")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	runs_root = "user://golden_runs_%d" % (hash(out_dir) & 0xffffff)
	var started := Time.get_ticks_msec()
	for section in [_fights, _fight_variants, _odds, _regions_and_tuning, _autoplay, _tools]:
		var t := Time.get_ticks_msec()
		section.call()
		print("  %s: %.1f s" % [section.get_method(), (Time.get_ticks_msec() - t) / 1000.0])
	var tj := Time.get_ticks_msec()
	await _journals()
	print("  _journals: %.1f s" % ((Time.get_ticks_msec() - tj) / 1000.0))
	print("golden capture written to %s in %.1f s" % [out_dir, (Time.get_ticks_msec() - started) / 1000.0])
	quit(0)


# --- Output -------------------------------------------------------------------

func _write(name: String, text: String) -> void:
	var path := out_dir.path_join(name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## A canonical text form of any value: objects by their script variables,
## recursively; wall-clock fields left out.
static func dump(v: Variant, depth := 0, seen: Array = []) -> String:
	var pad := "  ".repeat(depth)
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return var_to_str(v)
		TYPE_FLOAT:
			return var_to_str(v)
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return "<%s>" % type_string(typeof(v))
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
				TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY:
			if v.is_empty():
				return "[]"
			var parts := PackedStringArray()
			for item: Variant in v:
				parts.append(pad + "  " + dump(item, depth + 1, seen))
			return "[\n" + ",\n".join(parts) + "\n" + pad + "]"
		TYPE_DICTIONARY:
			if (v as Dictionary).is_empty():
				return "{}"
			var parts := PackedStringArray()
			for k: Variant in v:
				if str(k) in VOLATILE_KEYS:
					continue
				parts.append("%s  %s: %s" % [pad, var_to_str(k), dump(v[k], depth + 1, seen)])
			return "{\n" + ",\n".join(parts) + "\n" + pad + "}"
		TYPE_OBJECT:
			if v == null:
				return "null"
			var obj: Object = v
			if obj in seen:
				return "<cycle %s>" % _class_of(obj)
			if depth > 8:
				return "<deep %s>" % _class_of(obj)
			if obj is Resource and obj.get_script() == null:
				return "<%s %s>" % [obj.get_class(), (obj as Resource).resource_path]
			seen.append(obj)
			# Sorted by name: where a variable is declared (or inherited from)
			# is not behaviour.
			var names := PackedStringArray()
			for p in obj.get_property_list():
				if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not p.name in VOLATILE_KEYS and not p.name in names:
					names.append(p.name)
			names.sort()
			var parts := PackedStringArray()
			for n in names:
				parts.append("%s  %s = %s" % [pad, n, dump(obj.get(n), depth + 1, seen)])
			seen.erase(obj)
			return _class_of(obj) + " {\n" + "\n".join(parts) + "\n" + pad + "}"
		_:
			return var_to_str(v)


static func _class_of(obj: Object) -> String:
	var s: Script = obj.get_script()
	if s != null:
		var n := s.get_global_name()
		if n != &"":
			return n
		return s.resource_path.get_file() if not s.resource_path.is_empty() else "inner"
	return obj.get_class()


# --- Fights -------------------------------------------------------------------

func _squad(seed_value: int) -> Array[SquadMemberSummary]:
	return BotSquadProvider.new(BotFactory.new(BotTuning.load_default()).build_squad(seed_value)).get_squad()


func _policy(name: String) -> FightPolicy:
	match name:
		"random":
			return RandomFightPolicy.new()
		"intent":
			return IntentFightPolicy.new()
		"patient":
			return PatientFightPolicy.new()
	return SimpleFightPolicy.new()


func _fight_text(fight: Fight) -> String:
	var lines := PackedStringArray()
	lines.append(fight.log_text())
	lines.append("-- action tags: " + ", ".join(fight.action_tags))
	for t in fight.decision_tags:
		lines.append("-- tag " + dump(t))
	var r := fight.result()
	lines.append("-- result outcome=%d grid=%s rewards=%s timed_out=%s" % [r.outcome, var_to_str(r.grid_cost), r.rewards, fight.timed_out])
	return "\n".join(lines) + "\n"


func _fights() -> void:
	var seeds := [1, 2, 7] if quick else [1, 2, 3, 7, 11, 42]
	var kinds := {"attack": FightRequest.Kind.ATTACK, "defend": FightRequest.Kind.DEFEND}
	for s: int in seeds:
		var squad := _squad(s)
		for kind_name: String in kinds:
			for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
				for pol in ["simple", "random", "intent", "patient"]:
					var req := FightRequest.new(kinds[kind_name], "golden_%d" % level, level, squad)
					var fight := HeadlessFightRunner.run(req, s * 1000 + level, _policy(pol), IntentFightPolicy.new())
					_write("fights/s%d_%s_l%d_%s.txt" % [s, kind_name, level, pol], _fight_text(fight))
		# A chain of fights applied to the bots: skill ranks and personality drift.
		var bots := BotFactory.new(BotTuning.load_default()).build_squad(s)
		var ledger := SkillUseLedger.new()
		var growth := PackedStringArray()
		for i in 6:
			var req := FightRequest.new(FightRequest.Kind.ATTACK, "chain", i % 6,
				BotSquadProvider.new(bots).get_squad())
			var fight := HeadlessFightRunner.run(req, s * 77 + i, PatientFightPolicy.new(), IntentFightPolicy.new())
			var report := PostFight.apply(fight, bots.get_fielded(), ledger)
			growth.append("fight %d: %s" % [i, dump(report)])
		growth.append("squad after: " + dump(bots))
		growth.append("ledger after: " + dump(ledger))
		_write("growth/s%d.txt" % s, "\n".join(growth) + "\n")
		# Previews: every unit's preview and every choice's preview at each decision.
		var preview_lines := PackedStringArray()
		var preq := FightRequest.new(FightRequest.Kind.ATTACK, "preview", 2, squad)
		var pf := Fight.new(preq, s)
		var preview := FightPreview.new()
		var planner := IntentPlanner.new()
		var policy := SimpleFightPolicy.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var steps := 0
		var actor := pf.advance()
		while actor != null and steps < (12 if quick else 30):
			steps += 1
			var intents: Dictionary = planner.plan_all(pf)
			preview_lines.append("step %d actor %s units %s" % [steps, actor.id, dump(preview.units(pf, intents))])
			for skill in actor.skills():
				for target in pf.combatants:
					var action := FightAction.use(skill.id, target.id)
					if pf.check_action(action).is_empty():
						var choice := preview.preview_choice(pf, action)
						preview_lines.append("  choice %s->%s %s" % [skill.id, target.id, dump(choice)])
						preview_lines.append("  badges %s" % dump(BattleReadout.choice_badges(pf, action, choice)))
			preview_lines.append("  intents %s" % dump(intents))
			if true:
				preview_lines.append("  intent badges %s" % dump(BattleReadout.intent_badges(pf, intents)))
			pf.submit(policy.choose(pf, actor, rng))
			actor = pf.advance()
		_write("previews/s%d.txt" % s, "\n".join(preview_lines) + "\n")


func _fight_variants() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FightVariants.DEFAULT_PATH))
	var squad := _squad(5)
	for entry: Dictionary in data.decisions:
		if entry.get("layer", "") != FightVariants.LAYER:
			continue
		for opt: Dictionary in entry.get("options", []):
			var v := FightVariants.defaults()
			if not v.choose(entry.id, opt.id):
				continue
			var tuning := CombatTuning.load_default().with_variants(v)
			for level in [1, 4]:
				for pol in ["intent", "patient"]:
					var req := FightRequest.new(FightRequest.Kind.ATTACK, "variant", level, squad)
					var fight := HeadlessFightRunner.run(req, 900 + level, _policy(pol), IntentFightPolicy.new(), tuning)
					_write("variants/%s__%s_l%d_%s.txt" % [entry.id, opt.id, level, pol], _fight_text(fight))


func _odds() -> void:
	var lines := PackedStringArray()
	for s in [1, 2, 3]:
		var squad := _squad(s)
		var est := OddsEstimator.new()
		for level in range(0, 6):
			for kind in [FightRequest.Kind.ATTACK, FightRequest.Kind.DEFEND]:
				var e := est.estimate(squad, "odds_%d" % level, level, s, kind)
				lines.append("s%d l%d k%d: %s" % [s, level, kind, dump(e)])
	_write("odds.txt", "\n".join(lines) + "\n")


# --- Campaign -----------------------------------------------------------------

func _regions_and_tuning() -> void:
	for file in DirAccess.get_files_at("res://data/regions"):
		if file.get_extension() != "json":
			continue
		var map := RegionMap.load_file("res://data/regions".path_join(file))
		var text := dump(map)
		text += "\nstarting_ids=%s\n" % [map.starting_ids()]
		for start in map.start_options():
			text += "start %s\n" % dump(start)
		_write("regions/%s.txt" % file.get_basename(), text)
	var plan := ActPlan.load_file(CampaignAutoplay.ACTS_FILE)
	var plan_text := dump(plan) + "\n"
	for act in plan.act_count():
		var map := plan.load_map(act)
		var tuning := plan.load_tuning(act)
		plan_text += "act %d tuning %s\n" % [act, dump(tuning)]
		for start in map.start_options():
			var state := Campaign.new_run_state(map, tuning, start)
			plan_text += "act %d start %s state %s\n" % [act, start.id, dump(state.to_dict())]
			var path := runs_root + "_state.json"
			state.save_file(path)
			plan_text += "  saved: %s\n" % FileAccess.get_file_as_string(path)
			plan_text += "  reloaded: %s\n" % dump(RunState.load_file(path).to_dict())
	_write("act_plan.txt", plan_text)
	_write("tunings.txt", "combat %s\nbot %s\npost_fight %s\nodds %s\nescalation %s\nfactions %s\nenemies %s\nskill_ranks %s\nintent %s\npersonalities %s\npreview %s\ndev %s\nrun_data %s\nfight_variants %s\ncampaign_variants %s\n" % [
		dump(CombatTuning.load_default()), dump(BotTuning.load_default()), dump(PostFightTuning.load_default()),
		dump(OddsTuning.load_default()), dump(Escalation.load_data()), dump(FactionTable.load_default()),
		dump(EnemyTable.load_default()), dump(SkillRanks.load_default()), dump(IntentWeights.load_default()),
		dump(EnemyPersonalities.load_default()), dump(PreviewRules.load_default()), dump(DevToolSettings.load_default()),
		dump(RunDataSettings.load_default()), dump(FightVariants.defaults()), dump(CampaignVariants.defaults())])


func _autoplay() -> void:
	var seeds := [1, 2] if quick else [1, 2, 3, 4]
	for s: int in seeds:
		for pol in CampaignAutoplay.POLICIES:
			for grow in [false, true]:
				var auto := CampaignAutoplay.new()
				auto.policy = pol
				auto.grow = grow
				var record := auto.play(s)
				_write("autoplay/s%d_%s_%s.txt" % [s, pol, "grow" if grow else "fixed"],
					dump(record) + "\nsquad " + dump(auto._squad) + "\n")
	# Every campaign variant option, blind policy.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CampaignVariants.DEFAULT_PATH))
	for entry: Dictionary in data.decisions:
		if entry.get("layer", "") != CampaignVariants.LAYER:
			continue
		for opt: Dictionary in entry.get("options", []):
			var v := CampaignVariants.defaults()
			if not v.choose(entry.id, opt.id):
				continue
			var auto := CampaignAutoplay.new(v, v)
			_write("autoplay_variants/%s__%s.txt" % [entry.id, opt.id], dump(auto.play(3)) + "\n")


# --- Tools --------------------------------------------------------------------

func _tools() -> void:
	var runs := 4 if quick else 12
	for file in DirAccess.get_files_at("res://data/scenarios"):
		if file.get_extension() != "json" or file.begins_with("_"):
			continue
		var scenario := ScenarioFiles.load_scenario("res://data/scenarios".path_join(file))
		var report := BatchSimulator.run(scenario, runs * 2, 5, "")
		_write("tools/batch_%s.txt" % file.get_basename(), report.format_text() + "\n" + dump(report) + "\n")
	for decision in VariantComparison.comparable():
		var cmp := VariantComparison.run(decision, runs, 3, 2, "patient", "intent", 3)
		_write("tools/compare_%s.txt" % decision, cmp.format_text() + "\n")
	for decision in CampaignComparison.comparable():
		var cc := CampaignComparison.run(decision, 2, 3)
		_write("tools/campaign_compare_%s.txt" % decision, cc.format_text() + "\n")
	var rates := FactionWinRates.run(2 if quick else 4, 1)
	_write("tools/factions.txt", rates.format_text() + "\n" + rates.format_markdown() + "\n")
	var curve := BalanceCurve.run(2 if quick else 4, 1)
	_write("tools/balance_curve.txt", curve.format_text() + "\n" + curve.format_markdown() + "\n")
	var old := BalanceCurve.run(2, 1, {"speed-range": "wide", "strike-cost": "free", "tag-weight": "per_action",
		"difficulty-curve": "flat"})
	_write("tools/balance_curve_old.txt", old.format_text() + "\n")
	var losses := LossReport.run(2, 1)
	_write("tools/losses.txt", losses.format_text() + "\n" + losses.format_markdown() + "\n")
	var cal := OddsCalibration.run(2, 2, 1)
	_write("tools/odds_calibration.txt", cal.format_markdown() + "\n")
	_write("tools/fight_scenario.txt", dump(ScenarioFiles.load_scenario("res://data/scenarios/duo_vs_turret.json")) + "\n")


# --- Runs through RunFlow -----------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _remove_tree(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for sub in DirAccess.get_directories_at(abs):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(file))
	DirAccess.remove_absolute(abs)


func _normal_journal(lines: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in lines:
		var c: Dictionary = _strip_volatile(l)
		out.append(c)
	return out


func _strip_volatile(v: Variant) -> Variant:
	if v is Dictionary:
		var d := {}
		for k: Variant in v:
			if str(k) in VOLATILE_KEYS:
				d[k] = 0
			elif str(k) == "folder" or str(k) == "imported" or str(k) == "started" or str(k) == "updated" or str(k) == "dir":
				d[k] = "<path>"
			else:
				d[k] = _strip_volatile(v[k])
		return d
	if v is Array:
		return (v as Array).map(_strip_volatile)
	return v


func _journals() -> void:
	_remove_tree(runs_root)
	DirAccess.make_dir_recursive_absolute(runs_root)
	var seeds := [13] if quick else [13, 21, 34]
	for s: int in seeds:
		await _play_run(s, true)
	await _play_run(55, false)
	_remove_tree(runs_root)


func _play_run(run_seed: int, auto: bool) -> void:
	var flow: RunFlow = load("res://ui/run/run_flow.tscn").instantiate()
	flow.run_seed = run_seed
	flow.auto_fights = auto
	flow.variants_path = runs_root + "_variants.json"
	flow.fight_screen_tuning = Helpers.fast_tuning()
	flow.runs_root = runs_root.path_join("s%d" % run_seed)
	flow.folder_opener = func(_p: String) -> void: pass
	root.add_child(flow)
	await _frames(2)
	var screen := flow.draft_screen
	for i in screen.picker.squad_size():
		screen.cards[screen.picker.bots()[i].id].pressed.emit()
	screen.start_button.pressed.emit()
	await _frames(1)
	var actions := 0
	var limit := 40 if quick else 400
	if not auto:
		limit = 12
	while actions < limit and flow.stage != RunFlow.Stage.DRAFT and flow.run_over_screen == null:
		actions += 1
		var overworld: Control = flow.overworld
		if overworld == null:
			break
		var c: Campaign = overworld.campaign
		if c.is_lost() or c.is_defeated():
			break
		if flow.stage == RunFlow.Stage.FIGHT and not auto:
			await _play_battle(flow)
			continue
		if flow.stage == RunFlow.Stage.POST_FIGHT:
			flow.continue_to_map()
			await _frames(1)
			continue
		await _close_modal(overworld)
		if c.is_payload_due():
			if c.state.act >= 1:
				break
			overworld.zoom_out()
			await _frames(2)
			continue
		if not c.pending_defense().is_empty():
			overworld._on_defend()
			await _frames(3)
			continue
		var target := ""
		var best := 99
		for region in c.map.regions:
			if c.standing(region.id) == Campaign.Standing.IN_RANGE and region.defense < best:
				best = region.defense
				target = region.id
		if actions % 3 == 0 and not target.is_empty() and c.state.grid >= c.attack_grid_cost(target):
			flow._on_region_selected(target)
			overworld._on_attack(target)
			await _frames(3)
		elif actions % 5 == 1 and not c.state.owned.is_empty() and c.can_reinforce(c.state.owned[0]):
			overworld._on_reinforce(c.state.owned[0])
		else:
			overworld._on_wait()
	if flow.stage == RunFlow.Stage.FIGHT and not auto:
		await _play_battle(flow)
	if flow.overworld != null and auto:
		flow.save_run()
		(flow.overworld as Control)._on_wait()
		flow.load_run()
	var dir := flow.run_dir
	var journal := RunJournal.read_file(RunFolder.journal_path(dir))
	var normal := _normal_journal(journal)
	var name := "runs/s%d_%s" % [run_seed, "auto" if auto else "manual"]
	_write(name + "/journal.txt", dump(normal) + "\n")
	_write(name + "/timeline.txt", "\n".join(RunTimeline.lines(normal, true)) + "\n")
	var replay := RunReplay.new(journal)
	await replay.run()
	_write(name + "/replay.txt", "match=%s fights=%d snapshots=%d\n%s\n" % [
		replay.is_match(), replay.fights_played, replay.snapshots_checked, "\n".join(replay.mismatches)])
	_write(name + "/summary.txt", dump(_strip_volatile(RunFolder.read_summary(dir))) + "\n")
	var save := RunSave.load_file(RunFolder.save_path(dir))
	_write(name + "/save.txt", dump(save) + "\n" if save != null else "no save\n")
	flow.queue_free()
	await _frames(2)


func _play_battle(flow: RunFlow) -> void:
	var screen := flow.battle_screen
	if screen == null:
		await _frames(1)
		return
	var guard := 0
	while not screen.fight.is_over() and guard < 2000:
		guard += 1
		if not screen.handler.is_player_turn():
			await _frames(1)
			continue
		Helpers.play_support_turn_by_mouse(screen)
	var g := 0
	while flow.stage != RunFlow.Stage.POST_FIGHT and g < 60:
		await _frames(1)
		g += 1
	flow.continue_to_map()
	await _frames(1)


func _close_modal(overworld: Control) -> void:
	if overworld._modal.visible and overworld._modal_buttons.get_child_count() > 0:
		(overworld._modal_buttons.get_child(0) as Button).pressed.emit()
		await _frames(1)
