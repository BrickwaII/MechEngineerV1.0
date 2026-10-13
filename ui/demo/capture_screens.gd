extends SceneTree
## Before/after shots of the demo screens for UI pull requests: each scenario
## as it opens, then with a tooltip open on its first skill card (fights) or
## stat (maps, or a fight waiting on the enemy). Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/demo/capture_screens.gd -- <out_dir> [scenario id ...]
## With no ids it shoots the map, fight and boss scenarios of all three acts.

const DEFAULT_IDS: Array[String] = [
	"act1_map_early", "act1_fight", "act1_boss",
	"act2_map_early", "act2_fight", "act2_boss",
	"act3_map_early", "act3_fight", "act3_boss",
]

var out_dir := "user://capture_out"
var only: PackedStringArray = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
		only = args.slice(1)
	if only.is_empty():
		only = PackedStringArray(DEFAULT_IDS)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	for s in DemoScenario.load_all():
		if not s.id in only:
			continue
		var flow := DemoRunFlow.new()
		flow.scenario = s
		flow.folder_opener = func(_path: String) -> void: pass
		root.add_child(flow)
		await _frames(30 if s.kind == DemoScenario.KIND_FIGHT else 80)
		await _save(s.id)
		var target := _tip_target(flow, s.kind == DemoScenario.KIND_FIGHT)
		if target == null:
			target = _tip_target(flow, false)
		if target != null:
			# The tooltip closes once the pointer is away from its control.
			root.warp_mouse(target.get_global_rect().get_center())
			UiTooltip.show_at(target, target.global_position + Vector2(target.size.x * 0.5, target.size.y + 4))
			await _frames(3)
			await _save("%s_tooltip" % s.id)
			UiTooltip.hide_tooltip()
		flow.queue_free()
		await _frames(3)
	quit()


## The first visible skill card (fights) or icon stat (maps) with a tooltip.
func _tip_target(n: Node, fight: bool) -> Control:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree() and UiTooltip.spec(c).size() > 0:
			if (fight and c is SkillCard) or (not fight and c is IconStat):
				return c
		var found := _tip_target(c, fight)
		if found != null:
			return found
	return null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(file + ".png"))
	print("saved ", file)
