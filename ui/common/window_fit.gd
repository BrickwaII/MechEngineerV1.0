class_name WindowFit
extends RefCounted
## How the game fills its window, at any size: the view always covers the
## whole window (no black bars), and big windows get a bigger view, not a
## stretched picture.
##
## The root draws its canvas at one scale (content_scale_factor) over a
## content size equal to the window, so the view in interface pixels is
## window / scale. The scale is:
##   - Auto (interface size 0): the largest scale_step multiple that keeps the
##     view at least min_size (data/feel/settings.json "display"). Steps of 0.5
##     keep the 2x pixel art and body text crisp: 1920x1080 draws at 100% over
##     a 1920x1080 view, 2560x1440 at 150% over 1707x960.
##   - A fixed interface size, capped the same way, so a big size never pushes
##     the screens past the window's edge.
##   - Below min_size (a small fullscreen display) the view shrinks to fit
##     instead, so min_size is the smallest layout any screen has to handle.
##
## Presentation applies it at start and on every window resize.

## True while a check lays the root out at a fixed view (ScreenFit.emulate):
## apply() then leaves the root alone.
static var held := false

## The smallest view the layouts are built for, in interface pixels; also the
## smallest window.
static func min_size() -> Vector2:
	var v: Array = FeelData.settings().get("display", {}).get("min_size", [1280, 820])
	return Vector2(float(v[0]), float(v[1]))


static func scale_step() -> float:
	return float(FeelData.settings().get("display", {}).get("scale_step", 0.5))


## The canvas scale for a window of `window` pixels at interface size
## `requested` (0 for Auto).
static func scale_for(window: Vector2, requested := 0.0) -> float:
	var least := min_size()
	var fit := minf(window.x / least.x, window.y / least.y)
	if fit < 1.0:
		return fit
	var step := scale_step()
	var largest := maxf(1.0, floorf(fit / step + 0.0001) * step)
	if requested <= 0.0:
		return largest
	return clampf(snappedf(requested, step), 1.0, largest)


## The view in interface pixels for that window and interface size.
static func view_size(window: Vector2, requested := 0.0) -> Vector2:
	return window / scale_for(window, requested)


## True when interface size `requested` fits `window` uncapped.
static func fits(window: Vector2, requested: float) -> bool:
	return requested <= 0.0 or is_equal_approx(scale_for(window, requested), snappedf(requested, scale_step()))


## Sets the root's stretch so its view fills `root`'s window at the scale
## above. Safe to call on every resize: it only writes what changed.
static func apply(root: Window, requested := 0.0) -> void:
	if root == null or held:
		return
	var window := Vector2(root.size)
	if window.x <= 0.0 or window.y <= 0.0:
		return
	var scale := scale_for(window, requested)
	if root.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if root.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if root.content_scale_stretch != Window.CONTENT_SCALE_STRETCH_FRACTIONAL:
		root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	if root.content_scale_size != root.size:
		root.content_scale_size = root.size
	if not is_equal_approx(root.content_scale_factor, scale):
		root.content_scale_factor = scale


## The smallest window: min_size at 100%.
static func apply_min_size(root: Window) -> void:
	if root != null:
		root.min_size = Vector2i(min_size())


static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Fullscreen on or off. Leaving fullscreen goes back to a normal window.
static func set_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless" or on == is_fullscreen():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
