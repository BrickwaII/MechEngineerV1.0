extends CaptureScript
## Shots of the battle layout for pull requests: each fight and boss demo
## scenario on the player's turn, then with a skill focused (the lifted card
## and every target's outcome), the log and preview drawer open, compact
## cards, and a hovered unit with the other arrows faded. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/fight/demo/capture_battle_layout.gd -- <out_dir> [scenario id ...]

const DEFAULT_IDS: Array[String] = ["act1_fight", "act1_boss", "act2_fight", "act2_boss", "act3_fight", "act3_boss"]


func _init() -> void:
	start("user://capture_out", true, DEFAULT_IDS)


func _run() -> void:
	GameSettings.shared().animation_speed = "skip"
	for s in DemoScenario.load_all():
		if not s.id in only:
			continue
		var flow := DemoRunFlow.new()
		flow.scenario = s
		flow.folder_opener = func(_path: String) -> void: pass
		root.add_child(flow)
		await frames(20)
		var battle: BattleScreen = flow.battle_screen
		if battle != null:
			var guard := 0
			while not battle.handler.is_player_turn() and guard < 600:
				guard += 1
				await process_frame
			await frames(6)
			await save(s.id)
			await _focused(battle, s.id)
			battle.control_strip.press(&"log")
			battle.control_strip.press(&"preview")
			await frames(4)
			await save("%s_drawer" % s.id)
			battle.control_strip.press(&"log")
			battle.control_strip.press(&"preview")
			battle.control_strip.press(&"view", &"compact")
			await frames(4)
			await save("%s_compact" % s.id)
			battle.control_strip.press(&"view", &"detailed")
			await _hover(battle, s.id)
		flow.queue_free()
		await frames(3)
	GameSettings.shared().animation_speed = "1x"
	quit()


func _focused(battle: BattleScreen, id: String) -> void:
	var actor := battle.handler.actor()
	for skill in actor.skills():
		if skill.is_damage() and battle.handler.skill_problem(skill.id).is_empty():
			battle.on_skill_pressed(skill.id)
			break
	if not battle.handler.is_choosing_target():
		return
	await frames(3)
	for c in battle.fight.living(Combatant.Side.ENEMY):
		if battle.handler.target_problem(c.id).is_empty():
			battle.on_unit_hovered(c.id, true)
			break
	await frames(6)
	await save("%s_focused" % id)
	battle.send(FightCommand.cancel())
	battle.on_unit_hovered(battle.hovered_id, false)
	await frames(3)


func _hover(battle: BattleScreen, id: String) -> void:
	for c in battle.fight.living(Combatant.Side.ENEMY):
		battle.on_unit_hovered(c.id, true)
		await frames(4)
		await save("%s_hover" % id)
		battle.on_unit_hovered(c.id, false)
		return
