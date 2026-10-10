class_name MapFx
extends RefCounted
## The map's moving parts, with no scene: how lit each region is under the
## cursor, the selection pop, region captures in progress, the pressure each
## ring shows as it fills toward the real value, and the clock that drives the
## ring pulse and the marching pending cost. The map view calls advance() every
## frame and draws from what it reads here. Timings: data/feel/screens.json "map".
##
## The animation speed setting scales every duration (skip makes them
## instant); reduced motion stops the pulses, the selection pop and the capture
## ring, and keeps the color changes.

var settings: GameSettings
## The region under the cursor, or "".
var hovered_id := ""
## Seconds since the clock started; drives the pulses.
var time := 0.0

## Region id -> how lit it is, 0 to 1.
var _hover := {}
## Seconds since the selection last changed, or -1 with nothing selected.
var _select_age := -1.0
## Region id -> seconds since its capture started.
var _captures := {}
## Region id -> the pressure its ring shows.
var _ring := {}
## Region id -> [from, to, elapsed] while the ring slides to a new value.
var _ring_moves := {}


func _init(p_settings: GameSettings = null) -> void:
	settings = p_settings


func set_hovered(region_id: String) -> void:
	hovered_id = region_id


func hover_amount(region_id: String) -> float:
	return _hover.get(region_id, 0.0)


## Restarts the selection pop.
func selected() -> void:
	_select_age = 0.0


## Extra outline width for the selection pop, from select_pop_px down to 0.
func select_pop_px() -> float:
	if _select_age < 0.0 or _s().reduced_motion:
		return 0.0
	var duration := ScreenFeel.seconds("map.select_ms", _s())
	if duration <= 0.0 or _select_age >= duration:
		return 0.0
	return ScreenFeel.number("map.select_pop_px") * (1.0 - _select_age / duration)


func start_capture(region_id: String) -> void:
	if ScreenFeel.seconds("map.capture_ms", _s()) <= 0.0:
		return
	_captures[region_id] = 0.0


func is_capturing(region_id: String) -> bool:
	return _captures.has(region_id)


func capturing_ids() -> Array:
	return _captures.keys()


## 0 when a capture starts, 1 when it is done (and for regions not capturing).
func capture_progress(region_id: String) -> float:
	if not _captures.has(region_id):
		return 1.0
	var duration := ScreenFeel.seconds("map.capture_ms", _s())
	return 1.0 if duration <= 0.0 else clampf(_captures[region_id] / duration, 0.0, 1.0)


## 1 at the start of a capture fading to 0 over capture_flash_ms.
func capture_flash(region_id: String) -> float:
	if not _captures.has(region_id):
		return 0.0
	var duration := ScreenFeel.seconds("map.capture_flash_ms", _s())
	return 0.0 if duration <= 0.0 else clampf(1.0 - _captures[region_id] / duration, 0.0, 1.0)


## The pressure a ring shows: it slides to `pressure` over ring_fill_ms when
## the value changes, and starts there the first time a region is seen.
func ring_pressure(region_id: String, pressure: float) -> float:
	if not _ring.has(region_id):
		_ring[region_id] = pressure
		return pressure
	var target: float = _ring_moves[region_id][1] if _ring_moves.has(region_id) else _ring[region_id]
	if not is_equal_approx(target, pressure):
		if ScreenFeel.seconds("map.ring_fill_ms", _s()) <= 0.0:
			_ring_moves.erase(region_id)
			_ring[region_id] = pressure
		else:
			_ring_moves[region_id] = [_ring[region_id], pressure, 0.0]
	return _ring[region_id]


## How far a ring swells right now, in pixels: 0 below the warning level or
## with reduced motion, a slow pulse from the warning level and a fast one
## once an attack is imminent.
func ring_pulse_px(pressure: float, tuning: MapTuning) -> float:
	if _s().reduced_motion or pressure < tuning.ring_warning_at:
		return 0.0
	var hz := ScreenFeel.number("map.ring_pulse_imminent_hz") if pressure >= tuning.imminent_at else ScreenFeel.number("map.ring_pulse_hz")
	return ScreenFeel.number("map.ring_pulse_px") * (0.5 + 0.5 * sin(TAU * hz * time))


## How far the pending-cost hatch has marched, in pixels (0 with reduced motion).
func pending_march_px() -> float:
	return 0.0 if _s().reduced_motion else time * ScreenFeel.number("map.pending_march_px_per_s")


## 0 to 1 brightness of the pending cost's breathing (a steady 1 with reduced motion).
func pending_pulse() -> float:
	if _s().reduced_motion:
		return 1.0
	var depth := ScreenFeel.number("map.pending_pulse_alpha")
	return 1.0 - depth * (0.5 + 0.5 * sin(TAU * ScreenFeel.number("map.pending_pulse_hz") * time))


## Forgets everything tied to the regions of a map, for a new act or a load.
func reset() -> void:
	hovered_id = ""
	_hover.clear()
	_select_age = -1.0
	_captures.clear()
	_ring.clear()
	_ring_moves.clear()


## True while something changes without the clock: hover fades, the selection
## pop, captures and ring fills.
func is_animating() -> bool:
	if not _captures.is_empty() or not _ring_moves.is_empty() or select_pop_px() > 0.0:
		return true
	for id: String in _hover:
		if not is_equal_approx(_hover[id], 1.0 if id == hovered_id else 0.0):
			return true
	return not hovered_id.is_empty() and not _hover.has(hovered_id)


func advance(delta: float) -> void:
	time += delta
	if _select_age >= 0.0:
		_select_age += delta
	var hover_s := ScreenFeel.seconds("map.hover_ms", _s())
	if not hovered_id.is_empty() and not _hover.has(hovered_id):
		_hover[hovered_id] = 0.0
	for id: String in _hover.keys():
		var target := 1.0 if id == hovered_id else 0.0
		_hover[id] = target if hover_s <= 0.0 else move_toward(_hover[id], target, delta / hover_s)
		if _hover[id] == 0.0 and id != hovered_id:
			_hover.erase(id)
	var capture_s := ScreenFeel.seconds("map.capture_ms", _s())
	for id: String in _captures.keys():
		_captures[id] += delta
		if capture_s <= 0.0 or _captures[id] >= capture_s:
			_captures.erase(id)
	var fill_s := ScreenFeel.seconds("map.ring_fill_ms", _s())
	for id: String in _ring_moves.keys():
		var move: Array = _ring_moves[id]
		move[2] += delta
		if fill_s <= 0.0 or move[2] >= fill_s:
			_ring[id] = move[1]
			_ring_moves.erase(id)
		else:
			_ring[id] = Tween.interpolate_value(move[0], move[1] - move[0], move[2], fill_s, Tween.TRANS_QUAD, Tween.EASE_OUT)


func _s() -> GameSettings:
	return settings if settings else GameSettings.shared()
