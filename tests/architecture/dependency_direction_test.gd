extends GdUnitTestSuite
## Fails when a folder imports one it must not. Rules live in layer_rules.gd
## and CLAUDE.md.

const LayerRules := preload("res://tests/architecture/layer_rules.gd")

var _rules: LayerRules


func before_test() -> void:
	_rules = LayerRules.new()


func test_project_follows_layer_rules() -> void:
	var files := _rules.read_project_files()
	assert_bool(files.is_empty()).override_failure_message("scanned no files").is_false()
	assert_array(_rules.find_violations(files)).is_empty()


# The cases below prove the checker catches what it should, using made-up files.

func test_bot_data_may_not_preload_fight() -> void:
	var files := {"res://bot_data/bot.gd": "const F := preload(\"res://fight/timeline.gd\")\n"}
	assert_array(_rules.find_violations(files)).has_size(1)


func test_fight_may_not_use_a_campaign_class_name() -> void:
	var files := {
		"res://campaign/run_state.gd": "class_name RunState\nextends RefCounted\n",
		"res://fight/fight.gd": "var state: RunState\n",
	}
	assert_array(_rules.find_violations(files)).contains_exactly(
		["res://fight/fight.gd: fight/ may not import campaign/"])


func test_fight_may_use_bot_data_and_contracts() -> void:
	var files := {
		"res://bot_data/bot.gd": "class_name Bot\n",
		"res://contracts/unit_stats.gd": "class_name UnitStats\n",
		"res://fight/fight.gd": "var b: Bot\nvar s: UnitStats\n",
	}
	assert_array(_rules.find_violations(files)).is_empty()


func test_contracts_may_not_import_anything() -> void:
	var files := {"res://contracts/x.gd": "extends \"res://bot_data/bot.gd\"\n"}
	assert_array(_rules.find_violations(files)).has_size(1)


func test_campaign_may_not_import_bot_data_or_fight() -> void:
	var files := {
		"res://bot_data/bot.gd": "class_name Bot\n",
		"res://campaign/map.gd": "var b: Bot\nvar f = load(\"res://fight/fight.gd\")\n",
	}
	assert_array(_rules.find_violations(files)).has_size(2)


func test_nothing_outside_ui_may_import_ui() -> void:
	var files := {
		"res://ui/hud.gd": "class_name Hud\n",
		"res://tools/debug.gd": "var h: Hud\n",
		"res://campaign/scene.tscn": "[ext_resource type=\"Script\" path=\"res://ui/hud.gd\" id=\"1\"]\n",
	}
	assert_array(_rules.find_violations(files)).has_size(2)


func test_ui_may_import_every_layer() -> void:
	var files := {
		"res://ui/screen.gd": "\n".join([
			"const A := preload(\"res://contracts/a.gd\")",
			"const B := preload(\"res://bot_data/b.gd\")",
			"const C := preload(\"res://fight/c.gd\")",
			"const D := preload(\"res://campaign/d.gd\")",
			"const E := preload(\"res://tools/e.gd\")",
		]),
	}
	assert_array(_rules.find_violations(files)).is_empty()


func test_campaign_and_ui_may_read_data_but_contracts_may_not() -> void:
	var files := {
		"res://campaign/map.gd": "const REGIONS := \"res://data/regions/act1.json\"\n",
		"res://ui/screen.gd": "const TUNING := \"res://data/tuning/overworld.json\"\n",
		"res://contracts/x.gd": "const T := \"res://data/tuning/overworld.json\"\n",
	}
	assert_array(_rules.find_violations(files)).contains_exactly(
		["res://contracts/x.gd: contracts/ may not import data/"])


func test_data_holds_no_code() -> void:
	var files := {"res://data/regions/helper.gd": "extends Node\n"}
	assert_array(_rules.find_violations(files)).has_size(1)


func test_comments_and_strings_do_not_count_as_class_use() -> void:
	var files := {
		"res://campaign/run_state.gd": "class_name RunState\n",
		"res://fight/fight.gd": "# RunState and res://campaign/x.gd are only mentioned here\nvar label := \"RunState\"\n",
	}
	assert_array(_rules.find_violations(files)).is_empty()


func test_uid_references_are_resolved() -> void:
	var files := {"res://bot_data/bot.gd": "const F := preload(\"uid://abc123\")\n"}
	var resolver := func(uid: String) -> String:
		return "res://fight/timeline.gd" if uid == "uid://abc123" else ""
	assert_array(_rules.find_violations(files, resolver)).has_size(1)
