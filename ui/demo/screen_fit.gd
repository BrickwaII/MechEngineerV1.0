class_name ScreenFit
extends RefCounted
## Does every play screen fit the view? Opens each screen (menus, draft, the
## demo scenarios' maps and fights, readout tabs, the Esc menu, ...) and
## checks the Controls on it:
##   - every visible Control lies inside the view (and inside any ancestor
##     that clips its children), and nothing stretched over its screen came
##     out bigger than that screen; content in a ScrollContainer only has to lie
##     inside the scroll area's own rect once scrolled, so it is skipped;
##   - no label or button text is cut off (clipped, trimmed with "...", or
##     more wrapped lines than show);
##   - the items of an HBoxContainer (top bars, control strips) do not
##     overlap each other.
## tests/ui/screen_fit_test.gd runs it headless at every view size the
## window sizes and interface sizes give (WindowFit); ui/demo/check_fit.gd
## runs it in a real window under xvfb and saves a picture of each screen.

## Window sizes the game supports; each is checked at every interface size.
const WINDOWS: Array[Vector2] = [
	Vector2(1280, 820), Vector2(1366, 768), Vector2(1600, 900), Vector2(1920, 1080),
	Vector2(2560, 1440), Vector2(3440, 1440),
]
const MAP_SCENARIOS: Array[String] = [
	"act1_map_early", "act1_map_late", "act1_pre_fight", "act1_forced_defense",
	"act2_map_early", "act2_map_late", "act2_fast_forward",
	"act3_map_early", "act3_map_late", "act3_globe",
]
const FIGHT_SCENARIOS: Array[String] = [
	"act1_fight", "act1_boss", "act2_fight", "act2_boss", "act3_fight", "act3_boss",
]
## How far past an edge still counts as inside, for rounding.
const SLACK := 0.5


## Every screen id open() knows, in order.
static func screen_ids() -> Array[String]:
	var out: Array[String] = ["menu", "how_to_play", "settings", "whats_new", "load", "demo_picker", "draft",
		"run_map_crowded"]
	out.append_array(MAP_SCENARIOS)
	for id in FIGHT_SCENARIOS:
		for view in ["detailed", "compact"]:
			out.append("%s_%s" % [id, view])
	out.append_array(["esc_menu", "end_panel", "act3_run_over",
		"readout_summary", "readout_growth", "readout_details"])
	return out


## The distinct views (interface pixels) the supported windows give at every
## interface size in every scale mode, smallest first.
static func view_sizes() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for window in WINDOWS:
		for mode: String in FeelData.settings().get("scale_mode_options", [WindowFit.FIT]):
			for size: float in FeelData.settings().get("ui_scale_options", [0.0]):
				var view := WindowFit.view_size(window, size, mode).round()
				if not view in out:
					out.append(view)
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x * a.y < b.x * b.y)
	return out


## Opens screen `id` under `host` (a node in the tree whose viewport is the
## view to check) and lets it settle. Returns the node to free afterwards.
static func open(id: String, host: Node) -> Node:
	var tree := host.get_tree()
	var node: Node = null
	match id:
		"menu", "how_to_play", "load", "demo_picker":
			var menu: MainMenu = load("res://ui/main/main.tscn").instantiate()
			menu.show_whats_new = false
			menu.runs_root = "user://screen_fit_runs"
			host.add_child(menu)
			node = menu
			await _frames(tree, 4)
			if id == "how_to_play":
				menu.show_how_to_play()
			elif id == "load":
				menu.show_load_list()
			elif id == "demo_picker":
				menu.show_demos()
		"settings":
			node = SettingsScreen.open_overlay(host, GameSettings.new()).get_parent()
		"whats_new":
			node = WhatsNewCard.open(host, GameSettings.new()).get_parent()
		"run_map_crowded":
			# A run's map with every button its strips can show and long numbers.
			var map: Control = load("res://ui/overworld/overworld.tscn").instantiate()
			host.add_child(map)
			node = map
			await _frames(tree, 4)
			map.choose_start("")
			map.show_home_button(func() -> void: pass)
			map.show_run_buttons(true)
			var state: RunState = map.campaign.state
			state.energy = 99999.0
			state.material = 99999.0
			state.losses = 2
			map.log_event("A long line for the log, to see that it wraps rather than running off the panel's edge.")
			map._refresh()
			map._ff_button.visible = true
			map._status.text = "FIGHT IN PROGRESS"
			await _frames(tree, 4)
		"draft":
			node = load("res://ui/draft/draft_screen.tscn").instantiate()
			host.add_child(node)
			await _frames(tree, 60)
		"readout_summary", "readout_growth", "readout_details":
			var demo: Control = load("res://ui/post_fight/post_fight_demo.tscn").instantiate()
			host.add_child(demo)
			node = demo
			await _frames(tree, 2)
			demo.readout.skip()
			var tabs: UiTabs = demo.readout.find_children("*", "UiTabs", true, false)[0]
			tabs.select(StringName(id.trim_prefix("readout_")))
		"esc_menu", "end_panel":
			var flow := _demo_flow("act1_fight")
			host.add_child(flow)
			node = flow
			await _frames(tree, 30)
			if id == "esc_menu":
				flow.open_pause_menu()
			else:
				flow._show_end("Victory", "The demo fight is won.", "accent")
		_:
			var scenario := id
			var view := ""
			for v in ["_detailed", "_compact"]:
				if id.ends_with(v):
					scenario = id.trim_suffix(v)
					view = v.trim_prefix("_")
			var flow := _demo_flow(scenario)
			if flow == null:
				return null
			host.add_child(flow)
			node = flow
			await _frames(tree, 80)
			if not view.is_empty() and flow.battle_screen != null:
				await _focus_card(flow.battle_screen, view)
	await _frames(tree, 8)
	return node


static func _demo_flow(id: String) -> DemoRunFlow:
	for s in DemoScenario.load_all():
		if s.id == id:
			var flow := DemoRunFlow.new()
			flow.scenario = s
			flow.folder_opener = func(_path: String) -> void: pass
			return flow
	push_warning("ScreenFit: no demo scenario '%s'" % id)
	return null


## Waits for the squad's turn, sets the view and picks the first skill, so a
## card is focused with its targets' outcomes showing.
static func _focus_card(battle: BattleScreen, view: String) -> void:
	var guard := 0
	while is_instance_valid(battle) and not battle.fight.is_over() and not battle.handler.is_player_turn() and guard < 600:
		await battle.get_tree().process_frame
		guard += 1
	if not is_instance_valid(battle):
		return
	battle.control_strip.press(&"view", StringName(view))
	if battle.handler.is_player_turn():
		for skill in battle.handler.actor().skills():
			if battle.handler.skill_problem(skill.id).is_empty():
				battle.send(FightCommand.select_skill(skill.id))
				break


static func _frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.process_frame


## Lays the root out as a view of exactly `view` interface pixels, whatever
## the window: how the headless test sees each size. WindowFit holds off
## until restore().
static func emulate(root: Window, view: Vector2) -> void:
	WindowFit.held = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_factor = 1.0
	root.content_scale_size = Vector2i(view)


## Back to fitting the window.
static func restore(root: Window) -> void:
	WindowFit.held = false
	WindowFit.apply(root, GameSettings.shared().ui_scale, GameSettings.shared().scale_mode)


## Opens each screen in `ids` once and checks it at each of `views` (none:
## the window as it is). Returns screen id -> its problems, one line each with
## the view size in front; screens with none are left out. `shot`, if valid,
## is called with (screen id, view) after each check, for pictures.
static func run(host: Node, ids: Array[String], views: Array[Vector2] = [], shot := Callable()) -> Dictionary:
	var root := host.get_tree().root
	var found := {}
	for id in ids:
		var before := root.get_children()
		var node: Node = await open(id, host)
		if node == null:
			found[id] = ["the screen did not open"]
			continue
		# The screen, and what it opened on the root (modals, overlays).
		var parts: Array[Node] = [node]
		for child in root.get_children():
			if not child in before and child != node:
				parts.append(child)
		var lines: Array[String] = []
		for view in (views if not views.is_empty() else [Vector2.ZERO]):
			if view != Vector2.ZERO:
				emulate(root, view)
				await _frames(host.get_tree(), 4)
			var rect := root.get_visible_rect()
			for part in parts:
				if not is_instance_valid(part):
					continue
				for line in problems(part, rect):
					lines.append("%dx%d %s" % [rect.size.x, rect.size.y, line])
			if shot.is_valid():
				await shot.call(id, rect.size)
		if not lines.is_empty():
			found[id] = lines
		DetailModal.close_current()
		UiTooltip.hide_tooltip()
		for part in parts:
			if is_instance_valid(part):
				part.queue_free()
		root.get_tree().paused = false
		await _frames(host.get_tree(), 2)
	if not views.is_empty():
		restore(root)
	return found


## Every fit problem under `node` in the view `view`, one line each.
static func problems(node: Node, view: Rect2) -> Array[String]:
	var out: Array[String] = []
	_check(node, view, out)
	return out


static func _check(node: Node, bounds: Rect2, out: Array[String]) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	var inner := bounds
	if node is Control:
		var c := node as Control
		var rect := c.get_global_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0 and c.modulate.a > 0.0:
			if not bounds.grow(SLACK).encloses(rect):
				out.append("%s: %s is outside %s" % [_path(c), _r(rect), _r(bounds)])
			_check_text(c, out)
			_check_stretched(c, out)
			if c is HBoxContainer:
				_check_overlap(c as HBoxContainer, out)
		if c is ScrollContainer:
			return
		if c.clip_contents:
			inner = bounds.intersection(rect)
	elif node is CanvasLayer:
		# A layer draws in its own space; overlays sit at the origin.
		inner = bounds
	for child in node.get_children():
		_check(child, inner, out)


static func _check_text(c: Control, out: Array[String]) -> void:
	if c is Label:
		var l := c as Label
		if l.text.is_empty():
			return
		var font := l.get_theme_font("font")
		var size := l.get_theme_font_size("font_size")
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			if l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
				var longest := 0.0
				for line in l.text.split("\n"):
					longest = maxf(longest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
				if longest > l.size.x + SLACK:
					out.append("%s: text \"%s\" is cut off (%d > %d)" % [_path(l), l.text, longest, l.size.x])
		elif l.max_lines_visible < 0 and l.get_line_count() > l.get_visible_line_count():
			out.append("%s: text \"%s\" shows %d of %d lines" % [_path(l), l.text, l.get_visible_line_count(), l.get_line_count()])
	elif c is Button:
		var b := c as Button
		if b.text.is_empty() or not (b.clip_text or b.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING):
			return
		if b.size.x + SLACK < b.get_combined_minimum_size().x:
			out.append("%s: button \"%s\" is cut off" % [_path(b), b.text])


## A child stretched over its parent (anchored to both edges) that came out
## bigger than the parent's room: its contents' minimum size pushed it past
## the screen it belongs to, even if the window still has room below.
static func _check_stretched(c: Control, out: Array[String]) -> void:
	var parent := c.get_parent() as Control
	if parent == null or parent is Container or c.top_level:
		return
	var room := parent.size
	if is_equal_approx(c.anchor_left, 0.0) and is_equal_approx(c.anchor_right, 1.0):
		if c.size.x > room.x - c.offset_left + c.offset_right + SLACK:
			out.append("%s: %d wide, more than the %d its screen has" % [_path(c), c.size.x, room.x - c.offset_left + c.offset_right])
	if is_equal_approx(c.anchor_top, 0.0) and is_equal_approx(c.anchor_bottom, 1.0):
		if c.size.y > room.y - c.offset_top + c.offset_bottom + SLACK:
			out.append("%s: %d tall, more than the %d its screen has" % [_path(c), c.size.y, room.y - c.offset_top + c.offset_bottom])


static func _check_overlap(box: HBoxContainer, out: Array[String]) -> void:
	var shown: Array[Control] = []
	for child in box.get_children():
		if child is Control and (child as Control).visible and not (child as Control).top_level:
			if (child as Control).size.x > 0.0:
				shown.append(child)
	for i in range(1, shown.size()):
		var a := shown[i - 1].get_global_rect()
		var b := shown[i].get_global_rect()
		if a.end.x > b.position.x + SLACK:
			out.append("%s: %s overlaps %s" % [_path(box), shown[i - 1].name, shown[i].name])


static func _path(c: Node) -> String:
	var parts: Array[String] = []
	var n := c
	while n != null and parts.size() < 5:
		parts.push_front(str(n.name))
		n = n.get_parent()
	return "/".join(parts)


static func _r(r: Rect2) -> String:
	return "(%d,%d %dx%d)" % [r.position.x, r.position.y, r.size.x, r.size.y]
