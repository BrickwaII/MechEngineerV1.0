class_name HitPause
extends RefCounted
## Freezes game time for a moment when a hit lands (data/feel/feel.json
## "hit_pause": light_ms, heavy_ms). Everything that runs on game time
## (tweens, animations, meters) holds still; input and real-time timers do not.
## Overlapping pauses extend to the latest end, never stack.

static var _until_ms := 0
static var _active := false
static var _restore_scale := 1.0


## Starts a pause of the `kind` ("light" or "heavy") and returns its length in
## ms (0 when animations are skipped). Await `finished(tree)` to wait it out.
static func trigger(tree: SceneTree, kind := "light", settings: GameSettings = null) -> int:
	settings = settings if settings else GameSettings.shared()
	var ms := int(settings.scale_seconds(FeelData.number("hit_pause.%s_ms" % kind, 60.0)))
	if ms <= 0:
		return 0
	_until_ms = maxi(_until_ms, Time.get_ticks_msec() + ms)
	if not _active:
		_active = true
		_restore_scale = Engine.time_scale
		Engine.time_scale = FeelData.number("hit_pause.time_scale", 0.0)
		_hold(tree)
	return ms


static func is_active() -> bool:
	return _active


## Waits until no hit pause is running.
static func finished(tree: SceneTree) -> void:
	while _active:
		await tree.create_timer(0.01, true, false, true).timeout


static func _hold(tree: SceneTree) -> void:
	while Time.get_ticks_msec() < _until_ms:
		var left := (_until_ms - Time.get_ticks_msec()) / 1000.0
		await tree.create_timer(maxf(left, 0.001), true, false, true).timeout
	Engine.time_scale = _restore_scale
	_active = false
