extends CaptureScript
## Shots of the menus for pull requests: the main menu's entry tiles, the
## What's new card, every How to play page and the settings screen with the
## interface size. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/main/demo/capture_menus.gd -- <out_dir>


func _init() -> void:
	start("user://capture_out")


func _run() -> void:
	var menu: MainMenu = load("res://ui/main/main.tscn").instantiate()
	menu.runs_root = "user://capture_menu_runs"
	menu.show_whats_new = false
	root.add_child(menu)
	await frames(20)
	await save("main_menu")
	WhatsNewCard.open(menu, GameSettings.new())
	await frames(6)
	await save("whats_new")
	DetailModal.close_current()
	var guide := menu.show_how_to_play()
	for id in guide.tabs.ids():
		guide.tabs.select(id)
		await frames(4)
		await save("how_to_play_%s" % id)
	DetailModal.close_current()
	SettingsScreen.open_overlay(root, GameSettings.new())
	await frames(6)
	await save("settings")
	quit()
