extends CaptureScript
## Renders the combat rework's readouts on the battle screen (S7) to PNGs for
## pull requests. Battle Mode's Rework kit squad (Shred, Heavy Strike, Brace)
## against a Charger, a Plated and a Scaler, played by the careful policy
## (CarefulFightPolicy) through the screen's own commands; each shot is
## taken the first time its mechanic shows. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/fight/demo/capture_rework.gd -- <out_dir>
## Writes into <out_dir> (default ui/fight/screenshots):
##   rework_plating.png   plating pips on the Charger and the Plated
##   rework_exposed.png   Exposed on an enemy, its end marked on the timeline
##   rework_brace.png     a bot's Brace value, its end marked on the timeline
##   rework_wind_up.png   a committed wind-up: the card's flag, the intent chip, where it lands
##   rework_stagger.png   a Staggered enemy and its lost turn on the timeline
##   rework_focus_landing.png  Heavy Strike aimed: damage, cost, where the bot lands (AFTER bar), and
##                             its payoff: "N now. M if X puts Exposed on first"
##   rework_combo_setup.png    Shred aimed: "Then X's hit: N, M with Exposed", the plating it strips
##   rework_wait.png           pointing at WAIT: free, the Energy it banks, where the bot lands

const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")
const ENEMIES: Array[String] = ["charger_medium", "plated_medium", "scaler_medium"]
const MAX_DECISIONS := 60

var _taken := {}


func _init() -> void:
	start("res://ui/fight/screenshots")


func _screen(enemies: Array[String] = ENEMIES) -> BattleScreen:
	var squad: Array[SquadMemberSummary] = []
	for bot in BattleModeRun.preset_squad("rework").get_fielded():
		squad.append(bot.to_summary())
	var request := FightRequest.new(FightRequest.Kind.ATTACK, "harbor_district", 2, squad)
	var table := FixedEnemyTable.from_table(EnemyTable.load_default(), enemies)
	var screen: BattleScreen = BATTLE_SCENE.instantiate()
	screen.setup(request, 5, FightScreenTuning.load_default(), null, table)
	root.add_child(screen)
	return screen


func _run() -> void:
	var screen := _screen()
	await frames(20)
	await _focus_shots(screen)
	var policy := CarefulFightPolicy.new()
	var rng := RandomNumberGenerator.new()
	for n in MAX_DECISIONS:
		await until_player_turn(screen)
		if screen.fight.is_over():
			break
		screen.enemy_turn_delay = 1000.0
		await frames(10)
		await _shots(screen)
		if _taken.size() >= 5:
			break
		var actor := screen.handler.actor()
		var action := policy.choose(screen.fight, actor, rng)
		_send(screen, action)
		screen.enemy_turn_delay = 0.2
	screen.queue_free()
	await frames(2)
	await _wind_up_and_brace()
	quit()


## The careful policy breaks the Charger before it winds up and never needs a
## Brace, so a second fight leaves the Charger alone until it commits its
## Ram; the bot it aims at then Braces for it.
func _wind_up_and_brace() -> void:
	var screen := _screen(["charger_medium", "plated_medium", "plated_medium"] as Array[String])
	await frames(20)
	for n in MAX_DECISIONS:
		await until_player_turn(screen)
		if screen.fight.is_over():
			break
		screen.enemy_turn_delay = 1000.0
		await frames(10)
		await _shots(screen)
		if _taken.has("rework_brace") and _taken.has("rework_wind_up"):
			break
		var actor := screen.handler.actor()
		# Strike anything but the Charger, so it lives to wind up; the bot
		# its committed Ram aims at Braces.
		var action := FightAction.wait_for("strike")
		for c in screen.fight.living(Combatant.Side.ENEMY):
			if c.archetype == null or c.archetype.id != "charger":
				if screen.fight.check_action(FightAction.use("strike", c.id)).is_empty():
					action = FightAction.use("strike", c.id)
					break
		for c in screen.fight.living(Combatant.Side.ENEMY):
			if c.committed != null and c.committed.target_id() == actor.id \
					and screen.handler.skill_problem("brace").is_empty():
				action = FightAction.use("brace", actor.id)
		_send(screen, action)
		screen.enemy_turn_delay = 0.2


## The focused card's outlook on the first turn of a bot holding the whole
## kit: Heavy Strike and Shred aimed at the Plated, then WAIT pointed at.
func _focus_shots(screen: BattleScreen) -> void:
	await until_player_turn(screen)
	# Still pictures: the turn order's chips are placed, not mid-slide.
	var speed := GameSettings.shared().animation_speed
	GameSettings.shared().animation_speed = "skip"
	screen.enemy_turn_delay = 1000.0
	await frames(10)
	var plated: Combatant = null
	for c in screen.fight.living(Combatant.Side.ENEMY):
		if c.archetype != null and c.archetype.id == "plated":
			plated = c
	if plated == null:
		return
	for shot: Array in [["heavy_strike", "rework_focus_landing"], ["shred", "rework_combo_setup"]]:
		if not screen.handler.skill_problem(shot[0]).is_empty():
			continue
		screen.on_skill_pressed(shot[0])
		screen.preview_target(plated.id)
		await frames(40)
		await save(shot[1])
		screen.preview_target("")
		screen.on_cancel_pressed()
	screen.on_wait_hovered(true)
	await frames(40)
	await save("rework_wait")
	screen.on_wait_hovered(false)
	await frames(4)
	GameSettings.shared().animation_speed = speed


## Takes each shot the first time its mechanic is on the board.
func _shots(screen: BattleScreen) -> void:
	var f := screen.fight
	for c in f.living(Combatant.Side.ENEMY):
		if c.max_plating > 0 and c.plating < c.max_plating:
			await _once("rework_plating")
		if c.has_status("exposed"):
			await _once("rework_exposed")
		if c.committed != null:
			await _once("rework_wind_up")
		if c.staggered:
			await _once("rework_stagger")
	for c in f.living(Combatant.Side.PLAYER):
		if c.brace_absorb > 0:
			await _once("rework_brace")


func _once(file: String) -> void:
	if _taken.has(file):
		return
	_taken[file] = true
	await save(file)


static func _send(screen: BattleScreen, action: FightAction) -> void:
	if action == null:
		return
	if action.kind == FightAction.Kind.WAIT:
		screen.send(FightCommand.wait(action.skill_id, action.wait_ticks))
		return
	screen.send(FightCommand.select_skill(action.skill_id))
	if screen.handler.is_choosing_target():
		screen.send(FightCommand.select_target(action.target_id))
