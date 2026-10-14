extends SceneTree
## Shots of the menus for pull requests: the main menu's entry tiles, the
## What's new card, every How to play page and the settings screen with the
## interface size. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/main/demo/capture_menus.gd -- <out_dir>

var out_dir := "user://capture_out"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var menu: MainMenu = load("res://ui/main/main.tscn").instantiate()
	menu.runs_root = "user://capture_menu_runs"
	menu.show_whats_new = false
	root.add_child(menu)
	await _frames(20)
	await _save("main_menu")
	WhatsNewCard.open(menu, GameSettings.new())
	await _frames(6)
	await _save("whats_new")
	DetailModal.close_current()
	var guide := menu.show_how_to_play()
	for id in guide.tabs.ids():
		guide.tabs.select(id)
		await _frames(4)
		await _save("how_to_play_%s" % id)
	DetailModal.close_current()
	SettingsScreen.open_overlay(root, GameSettings.new())
	await _frames(6)
	await _save("settings")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(file + ".png"))
	print("saved ", file)
