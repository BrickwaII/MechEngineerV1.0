extends CaptureScript
## Renders the battle presentation to PNGs for pull requests. Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/fight/demo/capture_battle.gd -- <out_dir>
## Writes into <out_dir> (default ui/fight/screenshots):
##   battle_preview.png        a skill chosen, pointing at a target (choice preview on the units)
##   battle_mid_fight.png      the moment an attack lands
##   attack_strip_lv1_vs_max.png  Overcharge Shot at level 1 (top) and max level (bottom), frame by frame
##   ally_tiers.png            three bots in all three tiers, side by side
##   status_icons.png          every status on unit cards
##   victory.png               the victory moment

const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")
const UnitView := preload("res://ui/fight/unit_view.gd")
const UnitPanel := preload("res://ui/fight/unit_panel.gd")
const STRIP_TIMES_MS := [0, 90, 160, 230, 280, 330, 400, 500]


func _init() -> void:
	start("res://ui/fight/screenshots")


func _squad(level := 1) -> Array[SquadMemberSummary]:
	var out: Array[SquadMemberSummary] = []
	var defs := [
		["bolt", "Bolt", [["Strike", "damage_single", 1], ["Overcharge Shot", "damage_single_heavy", level]], UnitStats.new(40, 9, 4, 9, 2, 14)],
		["anvil", "Anvil", [["Strike", "damage_single", 1], ["Arc Sweep", "damage_all", level], ["Brace", "guard_self", 2]], UnitStats.new(44, 7, 6, 6, 3, 12)],
		["spark", "Spark", [["Strike", "damage_single", 1], ["Patch Up", "heal_single", 3], ["Shield Ally", "guard_ally", 1]], UnitStats.new(32, 6, 3, 7, 4, 13)],
	]
	for d: Array in defs:
		var skills: Array[Dictionary] = []
		for s: Array in d[2]:
			skills.append(SquadMemberSummary.make_skill(s[0], s[1], s[2]))
		out.append(SquadMemberSummary.new(d[0], d[1], d[3].hp, d[3].hp, "", d[3], skills))
	return out


## A Bot per squad member, so the tier rule has generations to read.
func _bots() -> Dictionary:
	var out := {}
	var gens := {"bolt": 3, "anvil": 2, "spark": 1}
	for id: String in gens:
		out[id] = Bot.new(id, id.capitalize(), UnitStats.new(40, 5, 3, 5, 1, 10), Personality.new(gens[id]))
	return out


func _screen(level := 1, defense := 3, seed_value := 11) -> BattleScreen:
	var screen: BattleScreen = BATTLE_SCENE.instantiate()
	var request := FightRequest.new(FightRequest.Kind.ATTACK, "harbor_district", defense, _squad(level))
	var tuning := FightScreenTuning.load_default()
	screen.setup(request, seed_value, tuning)
	var bots := _bots()
	screen.bot_source = func(id: String) -> Bot: return bots.get(id)
	root.add_child(screen)
	return screen


func _run() -> void:
	await _capture_battle()
	await _capture_strip()
	await _capture_tiers()
	await _capture_statuses()
	await _capture_victory()
	quit()


func _capture_battle() -> void:
	var screen := _screen()
	await frames(20)
	await until_player_turn(screen)
	var actor := screen.handler.actor()
	var skill := "heavy_strike" if actor.has_skill("heavy_strike") else "arc_sweep" if actor.has_skill("arc_sweep") else "strike"
	if not screen.handler.skill_problem(skill).is_empty():
		skill = "strike"
	screen.on_skill_pressed(skill)
	var target := screen.fight.living(Combatant.Side.ENEMY)[0]
	screen.preview_target(target.id)
	await frames(12)
	await save("battle_preview")
	screen.on_unit_clicked(target.id, MOUSE_BUTTON_LEFT)
	var beat := screen.presenter.queue[0] if not screen.presenter.queue.is_empty() else screen.presenter.current
	var began := Time.get_ticks_msec()
	var land_ms := int(beat.impact_at() * 1000.0) + 60
	while Time.get_ticks_msec() - began < land_ms:
		await process_frame
	await save("battle_mid_fight")
	screen.queue_free()
	await frames(4)


## One Overcharge Shot at level 1, then at max level, frame by frame.
func _capture_strip() -> void:
	var rows: Array[Image] = []
	for level in [1, SkillFx.max_level()]:
		var screen := _screen(level, 1, 3)
		await frames(20)
		await until_player_turn(screen)
		screen.enemy_turn_delay = 1000.0
		var bolt := screen.fight.combatant("bolt")
		var target := screen.fight.living(Combatant.Side.ENEMY)[0]
		var used := FightEvent.new(FightEvent.Kind.SKILL, 1, "bolt", target.id, "heavy_strike")
		used.skill_level = level
		used.amount = 0
		used.energy_before = bolt.energy()
		used.energy_after = bolt.energy()
		var hit := FightEvent.new(FightEvent.Kind.HIT, 1, "bolt", target.id, "heavy_strike")
		hit.amount = 6
		hit.max_hp = target.max_hp
		hit.hp_before = target.hp
		hit.hp_after = target.hp
		var events: Array[FightEvent] = [used, hit]
		var actor_rect := Rect2i(screen.unit_panels["bolt"].get_global_rect().grow(6))
		var target_rect := Rect2i(screen.unit_panels[target.id].get_global_rect().grow(30))
		var shots: Array[Image] = []
		var began := Time.get_ticks_msec()
		screen.presenter.present(events)
		for ms: int in STRIP_TIMES_MS:
			while Time.get_ticks_msec() - began < ms:
				await process_frame
			await RenderingServer.frame_post_draw
			var shot := root.get_texture().get_image()
			shot.convert(Image.FORMAT_RGBA8)
			var a := shot.get_region(actor_rect)
			var b := shot.get_region(target_rect)
			var pair := Image.create(a.get_width() + b.get_width() + 4, maxi(a.get_height(), b.get_height()), false, Image.FORMAT_RGBA8)
			pair.fill(FeelData.color("background"))
			pair.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i(0, (pair.get_height() - a.get_height()) / 2))
			pair.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(a.get_width() + 4, 0))
			shots.append(pair)
		rows.append(_strip(shots, "Lv %d" % level))
		screen.queue_free()
		await frames(4)
	var out := Image.create(rows[0].get_width(), rows[0].get_height() * 2 + 16, false, Image.FORMAT_RGBA8)
	out.fill(FeelData.color("background"))
	out.blit_rect(rows[0], Rect2i(Vector2i.ZERO, rows[0].get_size()), Vector2i.ZERO)
	out.blit_rect(rows[1], Rect2i(Vector2i.ZERO, rows[1].get_size()), Vector2i(0, rows[0].get_height() + 16))
	out.save_png(out_dir.path_join("attack_strip_lv1_vs_max.png"))
	print("saved attack_strip_lv1_vs_max")


## Frames in a grid, four to a row, at full size.
func _strip(shots: Array[Image], label: String) -> Image:
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var cols := 4
	var rows := ceili(shots.size() / float(cols))
	var out := Image.create(cols * w + (cols - 1) * 4, rows * h + (rows - 1) * 4, false, Image.FORMAT_RGBA8)
	out.fill(FeelData.color("panel_border"))
	for i in shots.size():
		out.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * (w + 4), (i / cols) * (h + 4)))
	print("strip ", label)
	return out


func _capture_tiers() -> void:
	var page := Control.new()
	page.theme = PixelTheme.theme()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(page)
	var back := ColorRect.new()
	back.color = FeelData.color("background")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(back)
	_label(page, "Ally tiers (tier-rule: generation 1, 2, 3)", Vector2(40, 24), "TitleLabel")
	var tiers := SpriteManifest.tiers()
	var tuning := CombatTuning.load_default()
	var ids := ["rivet", "dynamo", "flux", "ohm"]
	for c in tiers.size():
		_label(page, tiers[c].capitalize(), Vector2(260 + c * 300, 90), "")
	for r in ids.size():
		var skills: Array[String] = ["strike"]
		var unit := Combatant.new(ids[r], ids[r], Combatant.Side.PLAYER, 0, UnitStats.new(30, 5, 3, 5, 1, 10), 30, skills, tuning)
		var base := BattleArt.look_for(unit, 0, BattleTierRule.defaults())
		_label(page, ids[r].capitalize(), Vector2(40, 170 + r * 150), "DimLabel")
		for c in tiers.size():
			var look := base.duplicate()
			look["tier"] = tiers[c]
			var view := UnitView.new()
			view.position = Vector2(240 + c * 300, 120 + r * 150)
			view.size = UnitView.STAGE_SIZE + Vector2(40, 40)
			page.add_child(view)
			view.setup(look, false)
	await frames(10)
	await save("ally_tiers")
	page.queue_free()
	await frames(4)


func _capture_statuses() -> void:
	var screen := _screen(1, 4, 5)
	await frames(20)
	await until_player_turn(screen)
	screen.enemy_turn_delay = 1000.0
	var f := screen.fight
	var bolt := f.combatant("bolt")
	bolt.guard_percent = 40
	var anvil := f.combatant("anvil")
	anvil.begin_wait(10 * Combatant.MILLI)
	var spark := f.combatant("spark")
	spark.energy_milli = 1000
	var enemies := f.living(Combatant.Side.ENEMY)
	enemies[0].hp = 0
	screen.refresh()
	if enemies.size() > 1:
		screen.unit_panels[enemies[1].id].show_intent("aggressive", "charging Overload, then -> Bolt (?)", "changed: Bolt guarded", "wait")
	await frames(30)
	await save("status_icons")
	screen.queue_free()
	await frames(4)


func _capture_victory() -> void:
	var screen := _screen(4, 0, 2)
	await frames(10)
	var guard := 0
	while not screen.fight.is_over() and guard < 400:
		guard += 1
		if screen.handler.is_player_turn():
			var actor := screen.handler.actor()
			var target := screen.fight.opponents_of(actor)[0]
			screen.on_skill_pressed("strike")
			screen.on_unit_clicked(target.id, MOUSE_BUTTON_LEFT)
		else:
			screen.handler.resolve_enemy_turn()
	while screen.presenter.is_busy():
		await process_frame
	await frames(30)
	await save("victory")
	screen.queue_free()


func _label(parent: Node, text: String, at: Vector2, variation: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	if not variation.is_empty():
		l.theme_type_variation = StringName(variation)
	parent.add_child(l)
