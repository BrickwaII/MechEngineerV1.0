extends Control
## The two sample units from data/feel/sprite_manifest.json in all three tiers:
## three ally looks (each from a seed) and the enemy drone, then every
## animation of one ally side by side.

const LOOK_SEEDS := [1, 4, 6]
const CELL := Vector2(150, 150)

var sprites: Array[UnitSprite] = []
var anim_sprites: Array[UnitSprite] = []


func _ready() -> void:
	theme = PixelTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = FeelData.color("background")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	_label("Sample sprites: tiers", Vector2(32, 20), "TitleLabel")
	var columns := []
	for look_seed in LOOK_SEEDS:
		var look := SpriteManifest.ally_look("ally_frame", look_seed)
		columns.append(["ally_frame", look, "Ally %s" % look["palette"]])
	columns.append(["enemy_drone", {}, "Enemy drone"])
	for c in columns.size():
		_label(columns[c][2], Vector2(220 + c * CELL.x, 70), "DimLabel")
	var tiers := SpriteManifest.tiers()
	for r in tiers.size():
		var y := 110 + r * CELL.y
		_label(tiers[r].capitalize(), Vector2(32, y + 60), "")
		for c in columns.size():
			var sprite := UnitSprite.new()
			sprite.setup(columns[c][0], tiers[r], columns[c][1])
			sprite.position = Vector2(220 + c * CELL.x + 50, y + 60)
			add_child(sprite)
			sprites.append(sprite)

	_label("Animations (ally, medium)", Vector2(840, 70), "DimLabel")
	var look := SpriteManifest.ally_look("ally_frame", LOOK_SEEDS[0])
	var anims := SpriteManifest.animations().keys()
	for i in anims.size():
		var x := 860 + (i % 2) * 190
		var y := 110 + (i / 2) * 150
		var sprite := UnitSprite.new()
		sprite.setup("ally_frame", "medium", look)
		sprite.position = Vector2(x + 50, y + 60)
		add_child(sprite)
		sprite.play(anims[i])
		sprite.set_meta("anim", anims[i])
		anim_sprites.append(sprite)
		_label(anims[i], Vector2(x + 110, y + 50), "SmallLabel")
	var replay := Timer.new()
	replay.wait_time = 1.2
	replay.autostart = true
	replay.timeout.connect(_replay)
	add_child(replay)


## One-shot animations stop on their last frame; play them again.
func _replay() -> void:
	for sprite in anim_sprites:
		sprite.play(sprite.get_meta("anim"))


## Holds every animation on one frame (for screenshots).
func freeze_on(frame_share: float) -> void:
	for sprite in anim_sprites:
		var anim: StringName = sprite.get_meta("anim")
		var count := SpriteManifest.animations()[anim]["frames"] as int
		sprite.show_frame(anim, mini(count - 1, int(count * frame_share)))


func _label(text: String, at: Vector2, variation: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.theme_type_variation = variation
	add_child(label)
