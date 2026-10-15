extends CaptureScript
## Renders the battle readability readouts (R1-B) to PNGs for pull requests.
## Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/fight/demo/capture_readability.gd -- <out_dir>
## Writes into <out_dir> (default ui/fight/screenshots):
##   readability_arrow_badges.png   every enemy arrow with its damage badge
##   readability_ko_preview.png     a skill on a weakened enemy: the bot's arrow with a KO skull
##   readability_hp_slice.png       close-up: the hp slice on the target, the energy cost on the bot
##   readability_changed_arrows.png a hit that changes an enemy's plan: old number struck out
##   readability_stat_panels.png    stat chips on every card, and the detail card
##   readability_turn_order.png     hovering a unit lights its NEXT slots; WAIT previews the shift

const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")
const UnitDetail := preload("res://ui/fight/unit_detail.gd")


func _init() -> void:
	start("res://ui/fight/screenshots")


func _squad() -> Array[SquadMemberSummary]:
	var out: Array[SquadMemberSummary] = []
	var defs := [
		["bolt", "Bolt", [["Strike", "damage_single", 1], ["Overcharge Shot", "damage_single_heavy", 2]], UnitStats.new(40, 9, 4, 9, 2, 14)],
		["anvil", "Anvil", [["Strike", "damage_single", 1], ["Arc Sweep", "damage_all", 1], ["Brace", "guard_self", 2]], UnitStats.new(44, 7, 6, 6, 3, 12)],
		["spark", "Spark", [["Strike", "damage_single", 1], ["Patch Up", "heal_single", 3], ["Shield Ally", "guard_ally", 1]], UnitStats.new(32, 6, 3, 7, 4, 13)],
	]
	for d: Array in defs:
		var skills: Array[Dictionary] = []
		for s: Array in d[2]:
			skills.append(SquadMemberSummary.make_skill(s[0], s[1], s[2]))
		out.append(SquadMemberSummary.new(d[0], d[1], d[3].hp, d[3].hp, "", d[3], skills))
	return out


func _screen(defense := 3, seed_value := 11) -> BattleScreen:
	var screen: BattleScreen = BATTLE_SCENE.instantiate()
	var request := FightRequest.new(FightRequest.Kind.ATTACK, "harbor_district", defense, _squad())
	screen.setup(request, seed_value, FightScreenTuning.load_default())
	root.add_child(screen)
	return screen


func _run() -> void:
	await _capture_badges_ko_and_slices()
	await _capture_changed()
	await _capture_stats()
	await _capture_turn_order()
	quit()


func _capture_badges_ko_and_slices() -> void:
	var screen := _screen()
	await frames(20)
	await until_player_turn(screen)
	screen.enemy_turn_delay = 1000.0
	await frames(8)
	await save("readability_arrow_badges")
	var actor := screen.handler.actor()
	var skill := "heavy_strike" if actor.has_skill("heavy_strike") and screen.handler.skill_problem("heavy_strike").is_empty() else "strike"
	var target := screen.fight.living(Combatant.Side.ENEMY)[0]
	# Weaken the target for the shot, so the hit would down it.
	target.hp = mini(target.hp, 4)
	screen.refresh()
	screen.on_skill_pressed(skill)
	screen.preview_target(target.id)
	await frames(12)
	await save("readability_ko_preview")
	screen.preview_target("")
	target.hp = target.max_hp
	screen.refresh()
	screen.preview_target(target.id)
	await frames(12)
	# Close-up: the bot's card (energy cost) above the target's card (hp slice), 2x.
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	shot.convert(Image.FORMAT_RGBA8)
	var a := shot.get_region(Rect2i(screen.unit_panels[actor.id].get_global_rect().grow(4)))
	var b := shot.get_region(Rect2i(screen.unit_panels[target.id].get_global_rect().grow(4)))
	var out := Image.create(maxi(a.get_width(), b.get_width()), a.get_height() + b.get_height() + 8, false, Image.FORMAT_RGBA8)
	out.fill(FeelData.color("background"))
	out.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
	out.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(0, a.get_height() + 8))
	out.resize(out.get_width() * 2, out.get_height() * 2, Image.INTERPOLATE_NEAREST)
	out.save_png(out_dir.path_join("readability_hp_slice.png"))
	print("saved readability_hp_slice")
	screen.queue_free()
	await frames(4)


## A hit that makes an enemy change its plan: try each target until one does.
func _capture_changed() -> void:
	for seed_value in [11, 5, 3, 8, 13, 21]:
		var screen := _screen(3, seed_value)
		await frames(20)
		await until_player_turn(screen)
		screen.enemy_turn_delay = 1000.0
		var actor := screen.handler.actor()
		for skill in actor.skills():
			if not skill.targets_opponents() or not screen.handler.skill_problem(skill.id).is_empty():
				continue
			screen.on_skill_pressed(skill.id)
			for target in screen.fight.living(Combatant.Side.ENEMY):
				screen.preview_target(target.id)
				if screen.arrows.arrows.any(func(x: Dictionary) -> bool: return x.changed and not x.player and not x.ghost):
					await frames(12)
					await save("readability_changed_arrows")
					screen.queue_free()
					await frames(4)
					return
			screen.on_cancel_pressed()
		screen.queue_free()
		await frames(4)
	print("no changed arrow found")


func _capture_stats() -> void:
	var screen := _screen()
	await frames(20)
	await until_player_turn(screen)
	screen.enemy_turn_delay = 1000.0
	var enemy := screen.fight.living(Combatant.Side.ENEMY)[0]
	var panel: Control = screen.unit_panels[enemy.id]
	var card: Control = panel._make_custom_tooltip("")
	screen.add_child(card)
	await frames(2)
	card.position = (panel.global_position + Vector2(-card.size.x - 12, panel.size.y * 2.0 + 24)).round()
	var bot_panel: Control = screen.unit_panels["bolt"]
	var bot_card: Control = bot_panel._make_custom_tooltip("")
	screen.add_child(bot_card)
	await frames(2)
	bot_card.position = (bot_panel.global_position + Vector2(bot_panel.size.x + 12, 0)).round()
	await frames(6)
	await save("readability_stat_panels")
	screen.queue_free()
	await frames(4)


func _capture_turn_order() -> void:
	var screen := _screen()
	await frames(20)
	await until_player_turn(screen)
	screen.enemy_turn_delay = 1000.0
	# An enemy that acts within the bar.
	var enemy := screen.fight.living(Combatant.Side.ENEMY)[0]
	for id in screen.timeline_bar.shown_ids:
		if screen.fight.combatant(id).side == Combatant.Side.ENEMY:
			enemy = screen.fight.combatant(id)
			break
	screen.preview_target(enemy.id)
	await frames(10)
	await RenderingServer.frame_post_draw
	var hover := _bar_strip(screen, "Hover %s: its slots light up" % enemy.display_name)
	screen.preview_target("")
	# An empty battery, so WAIT has a skill to wait for; point at WAIT.
	screen.handler.actor().energy_milli = 0
	screen.on_wait_hovered(true)
	await frames(20)
	await RenderingServer.frame_post_draw
	var wait := _bar_strip(screen, "Point at WAIT: the order after the wait")
	var full := root.get_texture().get_image()
	full.convert(Image.FORMAT_RGBA8)
	var out := Image.create(full.get_width(), hover.get_height() + wait.get_height() + full.get_height() + 16, false, Image.FORMAT_RGBA8)
	out.fill(FeelData.color("background"))
	out.blit_rect(hover, Rect2i(Vector2i.ZERO, hover.get_size()), Vector2i.ZERO)
	out.blit_rect(wait, Rect2i(Vector2i.ZERO, wait.get_size()), Vector2i(0, hover.get_height() + 8))
	out.blit_rect(full, Rect2i(Vector2i.ZERO, full.get_size()), Vector2i(0, hover.get_height() + wait.get_height() + 16))
	out.save_png(out_dir.path_join("readability_turn_order.png"))
	print("saved readability_turn_order (order shifts: %s)" % screen.timeline_bar.showing_preview)
	screen.queue_free()
	await frames(4)


## The NEXT bar, cropped, at 2x.
func _bar_strip(screen: BattleScreen, _label: String) -> Image:
	var shot := root.get_texture().get_image()
	shot.convert(Image.FORMAT_RGBA8)
	var rect := Rect2i(screen.timeline_bar.get_global_rect().grow(4))
	rect.size.x = mini(rect.size.x, shot.get_width() / 2)
	var strip := shot.get_region(rect)
	strip.resize(strip.get_width() * 2, strip.get_height() * 2, Image.INTERPOLATE_NEAREST)
	return strip
