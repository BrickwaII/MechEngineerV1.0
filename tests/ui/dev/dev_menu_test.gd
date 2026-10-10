extends GdUnitTestSuite
## The dev menu: its screens, and a run that plays the switchboard's choices.

const SCENE := "res://ui/dev/dev_menu.tscn"


func test_lists_the_switchboard_and_a_play_button() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(1)
	var menu: Node = runner.scene()
	assert_object(menu.find_child("PlayRunButton", true, false)).is_not_null()
	var texts := []
	for b in menu.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	assert_bool(texts.any(func(t: String) -> bool: return t.begins_with("Variant switchboard"))).is_true()
