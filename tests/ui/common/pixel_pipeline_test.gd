extends GdUnitTestSuite
## The pixel-art pipeline: nearest filtering, integer scaling, no mipmaps, the
## pixel font and the shared theme.


func test_textures_draw_with_nearest_filtering_by_default() -> void:
	# The project setting's enum starts at Nearest = 0 (Linear = 1 is Godot's default).
	assert_int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")).is_equal(0)


## WindowFit scales the canvas in steps that put every art pixel (drawn at 2x)
## on a whole number of screen pixels; Godot's own integer mode letterboxed
## big windows in black.
func test_the_window_scales_by_crisp_steps() -> void:
	assert_str(ProjectSettings.get_setting("display/window/stretch/mode")).is_equal("canvas_items")
	assert_str(ProjectSettings.get_setting("display/window/stretch/aspect")).is_equal("expand")
	var art_px := float(UiIcons.kit("icon_scale", 2))
	assert_float(fmod(WindowFit.scale_step() * art_px, 1.0)).is_equal(0.0)
	for size: float in FeelData.settings()["ui_scale_options"]:
		assert_float(fmod(size * art_px, 1.0)).override_failure_message(str(size)).is_equal(0.0)


func test_no_asset_texture_has_mipmaps() -> void:
	for path in _files("res://assets", "png.import"):
		var text := FileAccess.get_file_as_string(path)
		# The font's page image is read by the font importer and skipped here.
		if text.contains("importer=\"skip\""):
			continue
		assert_bool(text.contains("mipmaps/generate=false")).override_failure_message(path).is_true()


func test_the_pixel_font_scales_by_whole_steps() -> void:
	var text := FileAccess.get_file_as_string(PixelTheme.FONT_PATH + ".import")
	assert_bool(text.contains("scaling_mode=1")).is_true()
	for size: String in ["small", "body", "title"]:
		assert_int(PixelTheme.font_size(size) % 10).override_failure_message(size).is_equal(0)


func test_the_saved_theme_matches_the_palette() -> void:
	var saved := PixelTheme.theme()
	var built := PixelTheme.build()
	assert_object(saved.default_font).is_not_null()
	assert_str(saved.default_font.resource_path).is_equal(PixelTheme.FONT_PATH)
	assert_int(saved.default_font_size).is_equal(PixelTheme.font_size("body"))
	for spec in [["font_color", "Label"], ["font_color", "TitleLabel"], ["font_color", "Button"],
			["font_disabled_color", "Button"], ["font_color", "AccentButton"]]:
		assert_object(saved.get_color(spec[0], spec[1])).override_failure_message(str(spec)) \
			.is_equal(built.get_color(spec[0], spec[1]))
	assert_object(saved.get_color("font_color", "Label")).is_equal(FeelData.color("text"))


func test_the_theme_styles_the_common_controls() -> void:
	var t := PixelTheme.theme()
	for spec in [["normal", "Button"], ["hover", "Button"], ["pressed", "Button"], ["disabled", "Button"],
			["panel", "PanelContainer"], ["panel", "Panel"], ["slider", "HSlider"], ["normal", "LineEdit"]]:
		assert_bool(t.has_stylebox(spec[0], spec[1])).override_failure_message(str(spec)).is_true()
	for spec in [["checked", "CheckBox"], ["grabber", "HSlider"], ["arrow", "OptionButton"]]:
		assert_bool(t.has_icon(spec[0], spec[1])).override_failure_message(str(spec)).is_true()


func test_every_status_has_its_own_icon() -> void:
	for name in ["guard", "charging", "waiting", "low_energy", "down", "intent_changed"]:
		assert_bool(ResourceLoader.exists("res://assets/ui/icons/status_%s.png" % name)).override_failure_message(name).is_true()


func test_every_asset_is_credited() -> void:
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	var patterns: Array[String] = []
	var regex := RegEx.create_from_string("`(assets/[^`]+)`")
	for m in regex.search_all(credits):
		patterns.append(m.get_string(1))
	assert_array(patterns).is_not_empty()
	for path in _files("res://assets", ""):
		var rel := path.trim_prefix("res://")
		if rel.get_extension() in ["import", "uid"] or rel.get_file() in ["README.md", "LICENSE.md"]:
			continue
		var listed := patterns.any(func(p: String) -> bool: return rel.match(p))
		assert_bool(listed).override_failure_message("%s is not listed in CREDITS.md" % rel).is_true()


func _files(dir_path: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_files(dir_path.path_join(sub), suffix))
	for file in dir.get_files():
		if suffix.is_empty() or file.ends_with(suffix):
			out.append(dir_path.path_join(file))
	return out
