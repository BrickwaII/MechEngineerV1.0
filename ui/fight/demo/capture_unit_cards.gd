extends CaptureScript
## Shots of the battle unit cards for pull requests (ui/README.md rule 8):
## each fight and boss demo scenario as it opens, then with the first enemy's
## detail modal open (stats, then skills), a damage badge's math tooltip, and a turn-order chip's
## tooltip. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/fight/demo/capture_unit_cards.gd -- <out_dir> [scenario id ...]

const DEFAULT_IDS: Array[String] = ["act1_fight", "act1_boss", "act2_fight", "act2_boss", "act3_fight", "act3_boss"]


func _init() -> void:
	start("user://capture_out", true, DEFAULT_IDS)


func _run() -> void:
	for s in DemoScenario.load_all():
		if not s.id in only:
			continue
		var flow := DemoRunFlow.new()
		flow.scenario = s
		flow.folder_opener = func(_path: String) -> void: pass
		root.add_child(flow)
		await frames(30)
		await save(s.id)
		var battle: BattleScreen = flow.battle_screen
		if battle != null:
			await _detail(battle, s.id)
			await _badge(battle, s.id)
			await _turn(battle, s.id)
		flow.queue_free()
		await frames(3)
	quit()


func _detail(battle: BattleScreen, id: String) -> void:
	var enemy := ""
	if not battle.boss_id.is_empty():
		enemy = battle.boss_id
	else:
		for c in battle.fight.living(Combatant.Side.ENEMY):
			enemy = c.id
			break
	if enemy.is_empty():
		return
	var modal := battle.open_unit_detail(enemy)
	await frames(4)
	await save("%s_detail" % id)
	modal.tabs.select(&"skills")
	await frames(4)
	await save("%s_detail_skills" % id)
	DetailModal.close_current()
	await frames(2)


func _badge(battle: BattleScreen, id: String) -> void:
	await frames(2)
	for b: Dictionary in battle.arrows.badge_rects:
		var badge: ArrowBadge = b["badge"]
		var h := battle.arrows.hotspot_for(badge.from_id, badge.to_id)
		if h == null:
			continue
		root.warp_mouse(h.get_global_rect().get_center())
		UiTooltip.show_at(h, h.global_position + Vector2(h.size.x + 8, 0))
		await frames(3)
		await save("%s_badge" % id)
		UiTooltip.hide_tooltip()
		return


func _turn(battle: BattleScreen, id: String) -> void:
	for c in battle.timeline_bar.get_children():
		if c is PanelContainer and not (UiTooltip.spec(c).get("math", []) as Array).is_empty():
			var chip := c as Control
			root.warp_mouse(chip.get_global_rect().get_center())
			UiTooltip.show_at(chip, chip.global_position + Vector2(0, chip.size.y + 4))
			await frames(3)
			await save("%s_turn" % id)
			UiTooltip.hide_tooltip()
			return
