class_name SoundThrottle
extends RefCounted
## Keeps repeated sounds from stacking into noise: a sound id may start at most
## `max_count` times within any `window_ms`. Time is passed in, so it tests
## without waiting.

var _starts := {}


## True (and counts the start) when `id` may play at `now_ms`.
func try_start(id: StringName, now_ms: int, max_count: int, window_ms: int) -> bool:
	var recent: Array = _starts.get(id, [])
	var kept: Array = recent.filter(func(t: int) -> bool: return now_ms - t < window_ms)
	if kept.size() >= max_count:
		_starts[id] = kept
		return false
	kept.append(now_ms)
	_starts[id] = kept
	return true


func clear() -> void:
	_starts.clear()
