extends SceneTree
## Shots of the map's design-system UI for pull requests: each map demo
## scenario as it opens, then a selected region's card, every lens, the hover
## card, the region's detail modal, the "?" legend, and the Squad and Log
## tabs. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/overworld/capture_map_ui.gd -- <out_dir> [scenario id ...]

const DEFAULT_IDS: Array[String] = ["act1_map_early", "act2_map_late", "act3_map_early"]

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
		await _frames(80)
		await _save(s.id)
		var map = flow.overworld
		if map != null:
			await _map_shots(map, s.id)
		flow.queue_free()
		await _frames(3)
	quit()


func _map_shots(map, id: String) -> void:
	var target := ""
	for r in map.campaign.map.regions:
		if map.campaign.standing(r.id) == Campaign.Standing.IN_RANGE:
			target = r.id
			break
	if target.is_empty():
		return
	map.odds.finish_all()
	map.map_view.select(target)
	await _frames(4)
	await _save("%s_selected" % id)
	for lens in ["pressure", "resources", "odds"]:
		map.map_strip.press(&"lens", StringName(lens))
		await _frames(3)
		await _save("%s_lens_%s" % [id, lens])
	map.map_strip.press(&"lens", &"defense")
	var other := ""
	for r in map.campaign.map.regions:
		if r.id != target and map.map_view.pin_rects.has(r.id):
			other = r.id
			break
	if not other.is_empty():
		var rect: Rect2 = map.map_view.pin_rects[other]
		root.warp_mouse(map.map_view.get_global_transform() * rect.get_center())
		map._on_region_hovered(other)
		await _frames(3)
		await _save("%s_hover" % id)
		map._on_region_hovered("")
	DetailModal.open(map, map.region_detail_spec(target))
	await _frames(4)
	await _save("%s_detail" % id)
	DetailModal.close_current()
	map.map_strip.press(&"legend")
	await _frames(3)
	await _save("%s_legend" % id)
	map.map_strip.press(&"legend")
	map.side_tabs.select(&"squad")
	await _frames(3)
	await _save("%s_squad" % id)
	map.side_tabs.select(&"log")
	await _frames(3)
	await _save("%s_log" % id)
	map.side_tabs.select(&"region")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(file + ".png"))
	print("saved ", file)
