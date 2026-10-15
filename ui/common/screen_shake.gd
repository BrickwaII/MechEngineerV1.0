class_name ScreenShake
extends Node
## Shakes one node (a Camera2D's offset, or any Control's or Node2D's
## position) for big and small hits only. Presets live in data/feel/feel.json
## "shake"; strength follows the player's shake setting and is zero when shake
## is off or reduced motion is on. Offsets are whole pixels.
##
##     var shake := ScreenShake.new(battle_root)
##     add_child(shake)
##     shake.shake("big")

var target: Node
var settings: GameSettings

var _base := Vector2.ZERO
var _elapsed := 0.0
var _duration := 0.0
var _amplitude := 0.0
var _frequency := 0.0
var _phase := 0.0
var _count := 0


func _init(p_target: Node = null, p_settings: GameSettings = null) -> void:
	target = p_target
	settings = p_settings


## Starts a shake from the "small" or "big" preset. Returns the amplitude used
## in pixels (0 means no shake happened).
func shake(kind := "small") -> float:
	var preset: Dictionary = FeelData.feel().get("shake", {}).get(kind, {})
	var amplitude := float(preset.get("amplitude_px", 0.0)) * _settings().shake_scale()
	var duration := _settings().scale_seconds(float(preset.get("ms", 0.0)) / 1000.0)
	if amplitude <= 0.0 or duration <= 0.0 or target == null:
		return 0.0
	if not is_shaking():
		_base = _read()
		_amplitude = amplitude
	else:
		_amplitude = maxf(amplitude, _remaining_amplitude())
	_elapsed = 0.0
	_duration = duration
	_frequency = float(preset.get("frequency_hz", 25.0))
	_count += 1
	_phase = _count * 1.7
	set_process(true)
	return amplitude


func is_shaking() -> bool:
	return _elapsed < _duration


func stop() -> void:
	if is_shaking():
		_write(_base)
	_elapsed = _duration


func _process(delta: float) -> void:
	advance(delta)


## Moves the shake forward by `delta` seconds; the target is back on its
## resting spot when the shake ends.
func advance(delta: float) -> void:
	if not is_shaking():
		set_process(false)
		return
	_elapsed += delta
	if _elapsed >= _duration:
		_write(_base)
		set_process(false)
		return
	_write(_base + offset_at(_elapsed, _duration, _amplitude, _frequency, _phase))


## The offset `t` seconds into a shake: two sines that decay to zero, rounded
## to whole pixels.
static func offset_at(t: float, duration: float, amplitude: float, frequency: float, phase := 0.0) -> Vector2:
	if duration <= 0.0 or t >= duration:
		return Vector2.ZERO
	var decay := pow(1.0 - t / duration, 2.0)
	var x := sin(TAU * frequency * t + phase) * amplitude * decay
	var y := sin(TAU * frequency * 1.31 * t + phase * 2.0) * amplitude * decay * 0.6
	return Vector2(roundf(x), roundf(y))


func _remaining_amplitude() -> float:
	return _amplitude * pow(1.0 - _elapsed / maxf(_duration, 0.001), 2.0)


func _settings() -> GameSettings:
	return settings if settings else GameSettings.shared()


func _read() -> Vector2:
	return target.offset if target is Camera2D else target.position


func _write(value: Vector2) -> void:
	if target is Camera2D:
		target.offset = value
	elif target is Control:
		# Shift all four offsets alike: setting position would write the
		# control's current size into its offsets, so an anchored screen
		# would keep that size after a resize or its contents shrinking.
		var c := target as Control
		var d: Vector2 = value - c.position
		c.offset_left += d.x
		c.offset_right += d.x
		c.offset_top += d.y
		c.offset_bottom += d.y
	else:
		target.position = value
