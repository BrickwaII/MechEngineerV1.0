extends SceneTree
## Renders escalation for the pull request: the alert meter and a tier news
## card after act 1 reaches Local Concern, then fortified regions and their
## news card some days later. Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/overworld/capture_escalation.gd -- <out_dir>

const OVERWORLD := "res://ui/overworld/overworld.tscn"

var out_dir := "res://ui/overworld/screenshots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var screen: Control = load(OVERWORLD).instantiate()
	screen.start_picker = func(options: Array) -> String: return options[0].id
	root.add_child(screen)
	await _settle(5)
	var c: Campaign = screen.campaign
	await _save("r2b_alert_unnoticed")
	# Take ground next to held ground until the alert rises.
	while c.escalation.tier() < 1:
		for region in c.map.regions:
			if c.standing(region.id) == Campaign.Standing.IN_RANGE:
				c._set_owned(region.id, true)
				break
	c.changed.emit()
	await _settle(90)
	await _save("r2b_alert_meter_and_news")
	screen.escalation_hud.news.clear()
	var per_level := int(Escalation.load_data().fortify.days_per_level)
	for i in per_level * c.escalation.max_fortify():
		c.escalation.advance_day()
	c.changed.emit()
	for region in c.map.regions:
		if c.escalation.fortify_of(region.id) > 0 and c.standing(region.id) == Campaign.Standing.IN_RANGE:
			screen.map_view.select(region.id)
			break
	await _settle(90)
	await _save("r2b_fortified_region")
	quit()


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
