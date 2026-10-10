class_name BattlePresenter
extends Control
## Plays each resolved action on the battlefield, one at a time: the actor
## winds up and strikes (or casts, or braces), projectiles fly, and at the
## impact the targets react, meters move, numbers pop, effects and sounds
## play, with a hit pause and, on big hits only, a small shake. Only the actor
## and its targets move; every other unit holds still until the beat ends.
##
## The fight itself has already moved on when a beat plays (logic never waits
## for animation). The meters are held at what the player has seen so far
## (shown_hp, shown_energy) and move when the beat shows the change. With the
## skip animation setting, or headless, beats resolve at once and nothing is
## spawned: the same bookkeeping, no visuals, no sound.
##
## Covers the battle screen as an overlay that ignores the mouse; effects,
## projectiles and popups are its children.

signal beat_started(beat: BattleBeat)
signal beat_landed(beat: BattleBeat)
## Every queued beat has played; meters may read the fight again.
signal idle

const PARTICLE_TEXTURE := preload("res://assets/sprites/particles/square_3.png")
const UnitView := preload("res://ui/fight/unit_view.gd")

var fight: Fight
## Unit id -> UnitPanel.
var panels: Dictionary = {}
var settings: GameSettings
## Shakes the battle screen on big hits.
var shake: ScreenShake
## Headless runs (tests, CI) resolve beats at once.
var headless := DisplayServer.get_name() == "headless"
## False plays beats with no effects, sounds, popups, pauses or shakes (tests).
var effects_enabled := true

var queue: Array[BattleBeat] = []
var current: BattleBeat
## Seconds into the current beat.
var clock := 0.0
## Unit id -> the hp its meter shows while a beat is pending.
var shown_hp_by_id: Dictionary[String, int] = {}
var shown_energy_by_id: Dictionary[String, int] = {}
## What the last beat played, for tests and the frame strips.
var last_sounds: Array[StringName] = []
var last_effects: Array[String] = []
var last_projectiles := 0
var last_hit_pause := ""
var last_shake := false

var _struck := false
var _landed := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func is_instant() -> bool:
	return headless or _settings().skips_animations()


func is_busy() -> bool:
	return current != null or not queue.is_empty()


func shown_hp(unit_id: String, actual: int) -> int:
	return shown_hp_by_id.get(unit_id, actual)


func shown_energy(unit_id: String, actual: int) -> int:
	return shown_energy_by_id.get(unit_id, actual)


## Queues one action's events for showing. Returns the beat, or null when
## there is nothing to show.
func present(events: Array[FightEvent]) -> BattleBeat:
	if events.is_empty():
		return null
	var beat := BattleBeat.from_events(fight, events, _settings())
	# Hold the meters at what the player has seen until the beat shows it.
	for e in events:
		match e.kind:
			FightEvent.Kind.SKILL, FightEvent.Kind.WAIT:
				if not shown_energy_by_id.has(e.actor_id):
					shown_energy_by_id[e.actor_id] = e.energy_before
			FightEvent.Kind.HIT, FightEvent.Kind.HEAL:
				if not shown_hp_by_id.has(e.target_id):
					shown_hp_by_id[e.target_id] = e.hp_before
	queue.append(beat)
	if is_instant():
		_drain_at_once()
	else:
		set_process(true)
	return beat


func _process(delta: float) -> void:
	advance(delta)


## Moves the beats forward by `delta` seconds of game time.
func advance(delta: float) -> void:
	if current == null:
		if queue.is_empty():
			set_process(false)
			return
		_begin(queue.pop_front(), true)
	clock += delta
	if not _struck and clock >= current.strike_at():
		_strike(current, true)
	if not _landed and clock >= current.impact_at():
		_land(current, true)
	if clock >= current.duration():
		_end(current, true)


func _drain_at_once() -> void:
	while not queue.is_empty():
		var beat: BattleBeat = queue.pop_front()
		_begin(beat, false)
		_strike(beat, false)
		_land(beat, false)
		_end(beat, false)


func _begin(beat: BattleBeat, visual: bool) -> void:
	current = beat
	clock = 0.0
	_struck = false
	_landed = false
	last_sounds = []
	last_effects = []
	last_projectiles = 0
	last_hit_pause = ""
	last_shake = false
	var lead := beat.lead()
	if lead != null and lead.kind == FightEvent.Kind.SKILL:
		shown_energy_by_id[beat.actor_id] = lead.energy_after
		_set_meters(beat.actor_id)
	beat_started.emit(beat)
	if not visual or not effects_enabled:
		_note_effects(beat)
		return
	_focus(beat)
	var view := _view(beat.actor_id)
	if view == null:
		return
	if lead != null and lead.kind == FightEvent.Kind.SKILL and lead.amount > 0:
		NumberPopup.spawn(self, _local(view.center_global()) + Vector2(0, 30), -lead.amount, "energy", _settings())
	match beat.motion():
		"cast":
			view.play(&"heal")
		"guard":
			view.play(&"guard")
		_:
			view.play(&"windup")
	if beat.kind == BattleBeat.Kind.WAIT:
		SoundPlayer.fire(&"charge")
		last_sounds.append(&"charge")
		_spawn_effect("charge", view.center_global(), BattleArt.color("energy"), 1.0)
		return
	var charge := str(beat.fx.get("charge_effect", ""))
	if not charge.is_empty():
		_spawn_effect(charge, view.center_global() + _facing(beat) * 30.0, SkillFx.tint(beat.fx, "accent"), float(beat.fx.get("scale", 1.0)))
	# Wind-up: draw back a little, away from the target.
	if beat.motion() in ["lunge", "slam", "sweep", "shoot", "blast"]:
		_move(view, -_facing(beat) * _px("recoil_px"), beat.windup, "attack_windup")


func _strike(beat: BattleBeat, visual: bool) -> void:
	_struck = true
	if beat.kind == BattleBeat.Kind.WAIT:
		return
	var sounds := SkillFx.sounds(beat.fx)
	last_projectiles = SkillFx.projectile_count(beat.fx)
	if not visual or not effects_enabled:
		last_sounds.append_array(sounds)
		return
	for id in sounds:
		SoundPlayer.fire(id)
		last_sounds.append(id)
	var view := _view(beat.actor_id)
	if view == null:
		return
	var motion := beat.motion()
	if motion in ["lunge", "slam", "sweep", "shoot", "blast"]:
		view.play(&"attack")
	var forward := _facing(beat)
	match motion:
		"lunge", "sweep":
			_move(view, forward * _px("lunge_px"), beat.strike, "attack_strike")
		"slam":
			_move(view, forward * _px("lunge_px") * 1.5, beat.strike, "attack_strike")
		"shoot", "blast":
			_move(view, -forward * _px("recoil_px"), beat.strike * 0.5, "attack_strike")
	var projectile := str(beat.fx.get("projectile", ""))
	if last_projectiles > 0 and not projectile.is_empty():
		var targets := beat.target_ids()
		if targets.is_empty():
			targets = [beat.aimed_at()]
		for i in last_projectiles:
			var target := _view(targets[i % targets.size()])
			if target == null:
				continue
			# Staggered so every projectile still lands at the impact.
			var delay := beat.strike * 0.35 * float(i) / maxf(1.0, last_projectiles - 1.0) if last_projectiles > 1 else 0.0
			var spread := Vector2(0, (i - (last_projectiles - 1) / 2.0) * 8.0)
			_spawn_projectile(projectile, view.center_global() + forward * 30.0 + spread,
				target.center_global() + spread * 0.5, beat.strike - delay, delay, beat.fx)


func _land(beat: BattleBeat, visual: bool) -> void:
	_landed = true
	var big := false
	var any_hit := false
	for e in beat.events:
		match e.kind:
			FightEvent.Kind.HIT:
				any_hit = true
				var is_big := SkillFx.is_big_hit(e.amount, e.max_hp, e.hp_after == 0)
				big = big or is_big
				shown_hp_by_id[e.target_id] = e.hp_after
				_set_meters(e.target_id)
				if visual and effects_enabled:
					_show_hit(beat, e, is_big)
			FightEvent.Kind.HEAL:
				shown_hp_by_id[e.target_id] = e.hp_after
				_set_meters(e.target_id)
				if visual and effects_enabled:
					_show_heal(beat, e)
			FightEvent.Kind.GUARD:
				if visual and effects_enabled:
					_show_guard(beat, e)
			FightEvent.Kind.DOWN:
				if visual and effects_enabled:
					_show_down(e)
				else:
					last_effects.append("down_burst")
	if any_hit:
		last_hit_pause = SkillFx.impact_kind(beat.fx, big)
		last_shake = big
		if visual and effects_enabled:
			HitPause.trigger(get_tree(), last_hit_pause, _settings())
			if big and shake != null:
				shake.shake("small")
	beat_landed.emit(beat)


func _end(beat: BattleBeat, visual: bool) -> void:
	if visual and effects_enabled:
		var view := _view(beat.actor_id)
		if view != null:
			_move(view, Vector2.ZERO, beat.recover, "attack_recover")
		for id: String in panels:
			_view(id).set_still(false)
	current = null
	if queue.is_empty():
		shown_hp_by_id.clear()
		shown_energy_by_id.clear()
		idle.emit()


## What a beat would spawn, recorded without spawning (instant beats, tests).
func _note_effects(beat: BattleBeat) -> void:
	var charge := str(beat.fx.get("charge_effect", ""))
	if not charge.is_empty():
		last_effects.append(charge)
	for e in beat.events:
		if e.kind in [FightEvent.Kind.HIT, FightEvent.Kind.HEAL, FightEvent.Kind.GUARD]:
			last_effects.append(str(beat.fx.get("impact_effect", "")))


func _show_hit(beat: BattleBeat, e: FightEvent, is_big: bool) -> void:
	var view := _view(e.target_id)
	if view == null:
		return
	var at := view.center_global()
	view.play(&"hit")
	_flash(view)
	var away := (at - _view(beat.actor_id).center_global()).normalized() if _view(beat.actor_id) != null else Vector2.RIGHT
	var push := Vector2(signf(away.x), 0) * _px("hit_knockback_px")
	var knock := view.create_tween()
	FeelTween.step(knock, view, "motion_offset", push, "ui_fast", _settings())
	FeelTween.step(knock, view, "motion_offset", Vector2.ZERO, "ui", _settings())
	NumberPopup.spawn(self, _local(at) + Vector2(0, -40), e.amount, "crit" if is_big else "damage", _settings())
	var scale_by := float(beat.fx.get("scale", 1.0))
	_spawn_effect(str(beat.fx.get("impact_effect", "hit_spark")), at, SkillFx.tint(beat.fx), scale_by)
	_burst(at, int(beat.fx.get("particles", 4)), SkillFx.tint(beat.fx, "accent"), scale_by)
	var impact_sound := str(beat.fx.get("impact_sound", ""))
	if not impact_sound.is_empty():
		SoundPlayer.fire(StringName(impact_sound))
		last_sounds.append(StringName(impact_sound))


func _show_heal(beat: BattleBeat, e: FightEvent) -> void:
	var view := _view(e.target_id)
	if view == null:
		return
	var at := view.center_global()
	if e.target_id != beat.actor_id:
		view.play(&"heal")
	NumberPopup.spawn(self, _local(at) + Vector2(0, -40), e.amount, "heal", _settings())
	var scale_by := float(beat.fx.get("scale", 1.0))
	_spawn_effect(str(beat.fx.get("impact_effect", "heal_plus")), at, SkillFx.tint(beat.fx), scale_by)
	# Extra sparks rise with the level.
	for i in int(beat.fx.get("extra", 0)) + 1:
		var offset := Vector2((i - int(beat.fx.get("extra", 0)) / 2.0) * 22.0, -10.0 - 8.0 * (i % 2))
		_spawn_effect("cross", at + offset, SkillFx.tint(beat.fx, "accent"), 0.67)
	_burst(at, int(beat.fx.get("particles", 4)), SkillFx.tint(beat.fx, "accent"), scale_by, true)


func _show_guard(beat: BattleBeat, e: FightEvent) -> void:
	var view := _view(e.target_id)
	if view == null:
		return
	var at := view.center_global()
	view.set_state(true, view.down)
	var scale_by := float(beat.fx.get("scale", 1.0))
	# One ring per step: the dome, then larger fainter rings.
	for i in int(beat.fx.get("extra", 0)) + 1:
		var tint := SkillFx.tint(beat.fx)
		tint.a = 1.0 - 0.25 * i
		_spawn_effect(str(beat.fx.get("impact_effect", "shield_shimmer")), at, tint, scale_by + 0.25 * i)
	_burst(at, int(beat.fx.get("particles", 4)), SkillFx.tint(beat.fx, "accent"), scale_by)


func _show_down(e: FightEvent) -> void:
	var view := _view(e.target_id)
	if view == null:
		return
	view.set_state(view.guarded, true)
	_spawn_effect("down_burst", view.center_global(), Color.WHITE, 1.0)
	SoundPlayer.fire(&"down")
	last_sounds.append(&"down")


## Only the actor and its targets move; the rest hold still.
func _focus(beat: BattleBeat) -> void:
	var involved := beat.target_ids()
	involved.append(beat.actor_id)
	for id: String in panels:
		_view(id).set_still(not id in involved)


func _set_meters(unit_id: String) -> void:
	var panel = panels.get(unit_id)
	var unit := fight.combatant(unit_id) if fight != null else null
	if panel == null or unit == null:
		return
	panel.set_meters(shown_hp(unit_id, unit.hp), shown_energy(unit_id, unit.energy()))


func _flash(view: UnitView) -> void:
	view.set_flash(1.0)
	var t := view.create_tween()
	t.tween_method(view.set_flash, 1.0, 0.0, maxf(0.01, FeelTween.seconds("ui", _settings())))


func _move(view: UnitView, offset: Vector2, seconds: float, preset: String) -> void:
	if _settings().reduced_motion:
		offset = Vector2.ZERO
	var t := view.create_tween()
	t.tween_property(view, "motion_offset", offset, maxf(0.01, seconds)) \
		.set_trans(FeelTween.transition(preset, _settings())).set_ease(FeelTween.easing(preset))


func _spawn_effect(name: String, at_global: Vector2, tint: Color, scale_by: float) -> void:
	var frames := BattleArt.effect_frames(name)
	if frames == null:
		return
	last_effects.append(name)
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = frames
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.position = _local(at_global).round()
	fx.scale = Vector2.ONE * snappedf(SpriteManifest.display_scale() * scale_by, 0.5)
	fx.modulate = tint
	fx.speed_scale = maxf(1.0, _settings().speed_multiplier())
	fx.z_index = 50
	add_child(fx)
	var anim: StringName = frames.get_animation_names()[0]
	fx.play(anim)
	fx.animation_finished.connect(fx.queue_free)


func _spawn_projectile(name: String, from_global: Vector2, to_global: Vector2, travel: float, delay: float, fx_spec: Dictionary) -> void:
	var frames := BattleArt.effect_frames(name)
	if frames == null:
		return
	var p := AnimatedSprite2D.new()
	p.sprite_frames = frames
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var from := _local(from_global)
	var to := _local(to_global)
	p.position = from.round()
	p.rotation = (to - from).angle()
	p.scale = Vector2.ONE * snappedf(SpriteManifest.display_scale() * float(fx_spec.get("scale", 1.0)), 0.5)
	p.modulate = SkillFx.tint(fx_spec)
	p.visible = delay <= 0.0
	p.z_index = 60
	add_child(p)
	p.play(frames.get_animation_names()[0])
	var t := p.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
		t.tween_callback(p.show)
	t.tween_property(p, "position", to.round(), maxf(0.01, travel)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(p.queue_free)


func _burst(at_global: Vector2, amount: int, color: Color, scale_by: float, rising := false) -> void:
	if amount <= 0:
		return
	var p := CPUParticles2D.new()
	p.position = _local(at_global).round()
	p.texture = PARTICLE_TEXTURE
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.4
	p.speed_scale = maxf(1.0, _settings().speed_multiplier())
	p.spread = 180.0
	p.direction = Vector2.UP
	p.initial_velocity_min = 70.0 * scale_by
	p.initial_velocity_max = 150.0 * scale_by
	p.gravity = Vector2(0, -60) if rising else Vector2(0, 320)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	p.z_index = 55
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _view(unit_id: String) -> UnitView:
	var panel = panels.get(unit_id)
	return panel.view if panel != null else null


## Toward the target: right for bots, left for enemies.
func _facing(beat: BattleBeat) -> Vector2:
	var unit := fight.combatant(beat.actor_id) if fight != null else null
	if unit == null:
		return Vector2.RIGHT
	var aimed := fight.combatant(beat.aimed_at())
	if aimed != null and aimed.side == unit.side:
		return Vector2.ZERO if aimed == unit else (Vector2.RIGHT if unit.side == Combatant.Side.PLAYER else Vector2.LEFT) * 0.5
	return Vector2.RIGHT if unit.side == Combatant.Side.PLAYER else Vector2.LEFT


func _px(key: String) -> float:
	return BattleArt.number(key, 0.0)


func _local(global_point: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * global_point


func _settings() -> GameSettings:
	return settings if settings else GameSettings.shared()
