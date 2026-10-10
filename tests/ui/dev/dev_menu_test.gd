extends GdUnitTestSuite
## The dev menu's map variant pickers, headless.

const SCENE := "res://ui/dev/dev_menu.tscn"


func test_there_is_one_picker_per_act_on_its_default_variant() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(1)
	var menu: Node = runner.scene()
	var picked := []
	for act in 3:
		var picker: OptionButton = menu.find_child("Act%dVariant" % (act + 1), true, false)
		assert_object(picker).is_not_null()
		picked.append(picker.get_item_metadata(picker.selected))
	assert_array(picked).is_equal(["lake_washington_12", "north_america_33", "world_20"])
	var act1: OptionButton = menu.find_child("Act1Variant", true, false)
	assert_int(act1.item_count).is_equal(4)
