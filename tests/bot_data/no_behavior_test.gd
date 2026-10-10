extends GdUnitTestSuite
## bot_data holds state and validation only.
##
## State classes (every Resource in bot_data/) may declare only constructors,
## validation and read-only accessors. Helpers that build, store or expose
## that state (factory, tuning reader, save file, squad provider) are plain
## RefCounted objects. Nothing in bot_data/ is a Node, runs per frame, handles
## input, emits signals, or imports fight/, campaign/ or ui/.

const LayerRules := preload("res://tests/architecture/layer_rules.gd")

const BOT_DATA_DIR := "res://bot_data"
const ENGINE_CALLBACKS := [
	"_ready", "_process", "_physics_process", "_input", "_unhandled_input",
	"_unhandled_key_input", "_shortcut_input", "_enter_tree", "_exit_tree", "_notification",
]
## Method names a state class may declare.
var _state_method_regex := RegEx.create_from_string(
	"^(_init|is_[a-z_]+|has_[a-z_]+|get_[a-z_]+|to_[a-z_]+|validation_errors(_for)?)$")


func _bot_data_scripts() -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at(BOT_DATA_DIR):
		if file.get_extension() == "gd":
			paths.append(BOT_DATA_DIR.path_join(file))
	return paths


func _own_methods(script: Script) -> Array[String]:
	var names: Array[String] = []
	for method in script.get_script_method_list():
		# Inline property setters show up as "@name_setter"; they only clamp.
		if not method.name.begins_with("@"):
			names.append(method.name)
	return names


func test_bot_data_has_scripts_to_check() -> void:
	assert_array(_bot_data_scripts()).is_not_empty()
	assert_bool(DirAccess.get_directories_at(BOT_DATA_DIR).is_empty()) \
		.override_failure_message("bot_data/ has subfolders; scan them too").is_true()


func test_nothing_is_a_node() -> void:
	for path in _bot_data_scripts():
		var base := (load(path) as Script).get_instance_base_type()
		assert_bool(base in [&"Resource", &"RefCounted"]) \
			.override_failure_message("%s extends %s" % [path, base]).is_true()


func test_nothing_runs_per_frame_or_handles_input() -> void:
	for path in _bot_data_scripts():
		for method in _own_methods(load(path)):
			assert_bool(method in ENGINE_CALLBACKS) \
				.override_failure_message("%s declares %s" % [path, method]).is_false()


func test_nothing_declares_signals() -> void:
	for path in _bot_data_scripts():
		assert_array((load(path) as Script).get_script_signal_list()) \
			.override_failure_message("%s declares signals" % path).is_empty()


func test_state_classes_declare_only_validation_and_accessors() -> void:
	var state_count := 0
	for path in _bot_data_scripts():
		var script: Script = load(path)
		if script.get_instance_base_type() != &"Resource":
			continue
		state_count += 1
		for method in _own_methods(script):
			assert_object(_state_method_regex.search(method)) \
				.override_failure_message("%s declares %s(), which is not state or validation" % [path, method]) \
				.is_not_null()
	# Bot, BotSquad, Personality, Skill, AugmentSlot.
	assert_int(state_count).is_greater_equal(5)


func test_the_layer_rules_keep_fight_campaign_and_ui_out_of_bot_data() -> void:
	for layer in ["fight", "campaign", "ui"]:
		assert_array(LayerRules.ALLOWED["bot_data"]).not_contains([layer])


func test_bot_data_follows_its_layer_rules() -> void:
	var rules := LayerRules.new()
	var files := rules.read_project_files()
	var violations := rules.find_violations(files).filter(
		func(v: String) -> bool: return v.begins_with(BOT_DATA_DIR + "/"))
	assert_array(violations).is_empty()


func test_bot_data_names_no_fight_campaign_or_ui_path() -> void:
	for path in _bot_data_scripts():
		var text := FileAccess.get_file_as_string(path)
		for forbidden in ["res://fight/", "res://campaign/", "res://ui/"]:
			assert_bool(text.contains(forbidden)) \
				.override_failure_message("%s names %s" % [path, forbidden]).is_false()


func test_the_checker_catches_a_state_class_with_behavior() -> void:
	var script := GDScript.new()
	script.source_code = "extends Resource\nvar hp := 3\nfunc take_damage(n: int) -> void:\n\thp -= n\n"
	assert_int(script.reload()).is_equal(OK)
	var offending := _own_methods(script).filter(
		func(m: String) -> bool: return _state_method_regex.search(m) == null)
	assert_array(offending).contains_exactly(["take_damage"])
