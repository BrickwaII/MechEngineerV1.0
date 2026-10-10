extends SceneTree
## Saves PixelTheme.build() to ui/common/pixel_theme.tres.
##     godot --headless --path . -s res://ui/common/build_theme.gd


func _init() -> void:
	var err := ResourceSaver.save(PixelTheme.build(), PixelTheme.THEME_PATH)
	print("saved %s: %s" % [PixelTheme.THEME_PATH, error_string(err)])
	quit(0 if err == OK else 1)
