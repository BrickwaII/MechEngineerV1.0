extends Control
## The feel kit on one screen: an ally and an enemy with ghost-bar meters.
## Buttons land a light hit, a big hit, a heal and an energy gain, each with
## its hit pause, shake, popup, sound and meter change; "Tweens" runs every
## preset side by side; F10 or "Settings" opens the settings screen.

var stage: Control
var ally: UnitSprite
var enemy: UnitSprite
var ally_hp: GhostBar
var ally_energy: GhostBar
var enemy_hp: GhostBar
var shake: ScreenShake
var tween_rows: Array[ColorRect] = []
var log_label: Label

var _hp := 100
var _energy := 40
var _busy := false


func _ready() -> void:
	theme = PixelTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = FeelData.color("background")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	stage = Control.new()
	stage.position = Vector2.ZERO
	stage.size = Vector2(1280, 820)
	add_child(stage)
	shake = ScreenShake.new(stage)
	add_child(shake)

	var title := Label.new()
	title.text = "Feel kit demo"
	title.theme_type_variation = "TitleLabel"
	title.position = Vector2(32, 24)
	stage.add_child(title)

	var floor_rect := ColorRect.new()
	floor_rect.color = FeelData.color("panel")
	floor_rect.position = Vector2(80, 360)
	floor_rect.size = Vector2(720, 8)
	stage.add_child(floor_rect)

	ally = UnitSprite.new()
	ally.setup("ally_frame", "advanced", SpriteManifest.ally_look("ally_frame", 3))
	ally.position = Vector2(240, 300)
	stage.add_child(ally)
	enemy = UnitSprite.new()
	enemy.setup("enemy_drone", "medium")
	enemy.position = Vector2(620, 290)
	stage.add_child(enemy)

	ally_hp = _bar("hp", Vector2(150, 390), "HP")
	ally_energy = _bar("energy", Vector2(150, 412), "EN")
	enemy_hp = _bar("hp", Vector2(530, 390), "HP")
	ally_hp.reset(_hp, 100)
	ally_energy.reset(_energy, 100)
	enemy_hp.reset(80, 100)

	var buttons := VBoxContainer.new()
	buttons.position = Vector2(900, 120)
	buttons.add_theme_constant_override("separation", 10)
	stage.add_child(buttons)
	for spec in [["Light hit", light_hit], ["Big hit", big_hit], ["Heal", heal],
			["Energy", gain_energy], ["Tweens", play_tweens], ["Settings (F10)", _open_settings]]:
		var button := Button.new()
		button.text = spec[0]
		button.custom_minimum_size = Vector2(260, 0)
		button.pressed.connect(spec[1])
		button.mouse_entered.connect(func() -> void: SoundPlayer.fire(&"ui_hover"))
		buttons.add_child(button)

	log_label = Label.new()
	log_label.theme_type_variation = "SmallLabel"
	log_label.position = Vector2(900, 470)
	stage.add_child(log_label)

	_build_tween_rows()


func _bar(kind: String, at: Vector2, text: String) -> GhostBar:
	var bar := GhostBar.new()
	bar.kind = kind
	bar.label = text
	bar.position = at
	bar.size = Vector2(200, 16)
	stage.add_child(bar)
	return bar


func _build_tween_rows() -> void:
	var y := 480.0
	var heading := Label.new()
	heading.text = "Tween presets (data/feel/feel.json)"
	heading.theme_type_variation = "DimLabel"
	heading.position = Vector2(32, y - 40)
	stage.add_child(heading)
	for name: String in FeelTween.names():
		var label := Label.new()
		label.text = "%s %d ms" % [name, int(FeelTween.preset(name)["ms"])]
		label.theme_type_variation = "SmallLabel"
		label.position = Vector2(32, y)
		stage.add_child(label)
		var dot := ColorRect.new()
		dot.color = FeelData.color("accent")
		dot.size = Vector2(12, 12)
		dot.position = Vector2(220, y)
		dot.set_meta("preset", name)
		stage.add_child(dot)
		tween_rows.append(dot)
		y += 28


## The enemy winds up and strikes; on impact a light hit lands on the ally.
func light_hit() -> void:
	await _enemy_attack(12, false)


func big_hit() -> void:
	await _enemy_attack(30, true)


func heal() -> void:
	ally.play("heal")
	SoundPlayer.fire(&"heal")
	_hp = mini(100, _hp + 18)
	ally_hp.set_value(_hp)
	NumberPopup.spawn(stage, ally.position + Vector2(0, -70), 18, "heal")
	_note("Heal: meter grows into its ghost, +18 popup with cross.")


func gain_energy() -> void:
	SoundPlayer.fire(&"energy_tick")
	_energy = mini(100, _energy + 15)
	ally_energy.set_value(_energy)
	NumberPopup.spawn(stage, ally.position + Vector2(30, -50), 15, "energy")
	_note("Energy: fills visibly, +15 EN popup with bolt.")


func play_tweens() -> void:
	SoundPlayer.fire(&"ui_click")
	for dot in tween_rows:
		dot.position.x = 220
		FeelTween.to(dot, "position:x", 520.0, dot.get_meta("preset"))


func _enemy_attack(damage: int, heavy: bool) -> void:
	if _busy:
		return
	_busy = true
	var home := enemy.position
	SoundPlayer.fire(&"charge" if heavy else &"swing")
	enemy.play("windup")
	var t := create_tween()
	FeelTween.step(t, enemy, "position:x", home.x + 12, "attack_windup")
	FeelTween.step(t, enemy, "position:x", ally.position.x + 150, "attack_strike")
	t.tween_callback(func() -> void: enemy.play("attack"))
	await t.finished
	_land_hit(damage, heavy)
	var back := create_tween()
	FeelTween.step(back, enemy, "position", home, "attack_recover")
	await back.finished
	enemy.play("idle")
	_busy = false


## Everything a landed hit does, in order: pause, flash, sound, popup, meter, shake.
func _land_hit(damage: int, heavy: bool) -> void:
	HitPause.trigger(get_tree(), "heavy" if heavy else "light")
	ally.play("hit")
	ally.set_flash(1.0)
	var flash := create_tween()
	flash.tween_method(ally.set_flash, 1.0, 0.0, FeelTween.seconds("ui_fast"))
	SoundPlayer.fire(&"hit_heavy" if heavy else &"hit_light")
	_hp = maxi(0, _hp - damage)
	ally_hp.set_value(_hp)
	NumberPopup.spawn(stage, ally.position + Vector2(0, -70), damage, "crit" if heavy else "damage")
	var amplitude := shake.shake("big" if heavy else "small")
	_note("%s hit: %d ms pause, shake %d px, -%d." % ["Big" if heavy else "Light",
		int(FeelData.number("hit_pause.%s_ms" % ("heavy" if heavy else "light"))), int(amplitude), damage])
	ally.animation_finished.connect(func(_a: StringName) -> void: ally.play("idle"), CONNECT_ONE_SHOT)
	if _hp <= 0:
		_hp = 100
		ally_hp.reset(_hp)


func _open_settings() -> void:
	SoundPlayer.fire(&"ui_confirm")
	SettingsScreen.open_overlay(get_tree().root)


func _note(text: String) -> void:
	log_label.text = text
