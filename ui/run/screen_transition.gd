class_name ScreenTransition
extends CanvasLayer
## The wipe between the run's screens (draft, map, battle, readout). Call
## cover() just before swapping screens: it freezes the last frame of the old
## screen over everything in vertical bands, then the bands fall away one
## after another to show the new screen. Timings: data/feel/screens.json
## "transition".
##
## The screens swap at once underneath, so nothing waits on the animation and
## input is never blocked: the bands ignore the mouse. With animations skipped
## there is no wipe. Headless there is no frame to freeze, so the bands are
## plain background color.

const LAYER := 40

var settings: GameSettings
## The bands in flight, left to right.
var bands: Array[Control] = []

var _tween: Tween


func _init() -> void:
	layer = LAYER
	name = "ScreenTransition"


func is_playing() -> bool:
	return _tween != null and _tween.is_running()


## Freezes the old screen and wipes it away. Returns false when there is no
## wipe (animations skipped, or not in the tree).
func cover() -> bool:
	var s := settings if settings else GameSettings.shared()
	var duration := ScreenFeel.seconds("transition.uncover_ms", s)
	# Nothing to wipe before the first frame is drawn.
	if duration <= 0.0 or not is_inside_tree() or Engine.get_frames_drawn() == 0:
		return false
	_clear()
	var view_size := get_viewport().get_visible_rect().size
	var frame: Texture2D = null
	if DisplayServer.get_name() != "headless":
		var image := get_viewport().get_texture().get_image()
		if image != null and not image.is_empty():
			frame = ImageTexture.create_from_image(image)
	var count := maxi(1, int(ScreenFeel.number("transition.bands", 1.0)))
	var width := ceilf(view_size.x / count)
	for i in count:
		var rect := Rect2(i * width, 0, width, view_size.y)
		var band: Control
		if frame != null:
			var piece := TextureRect.new()
			var atlas := AtlasTexture.new()
			atlas.atlas = frame
			atlas.region = Rect2(rect.position * Vector2(frame.get_size()) / view_size, rect.size * Vector2(frame.get_size()) / view_size)
			piece.texture = atlas
			piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			piece.stretch_mode = TextureRect.STRETCH_SCALE
			band = piece
		else:
			var plain := ColorRect.new()
			plain.color = FeelData.color("background")
			band = plain
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.position = rect.position
		band.size = rect.size
		add_child(band)
		bands.append(band)
	SoundPlayer.fire(&"screen_whoosh")
	# Each band drops and fades, starting a little after the one to its left.
	var stagger := ScreenFeel.number("transition.band_stagger") * duration / count
	_tween = create_tween().set_parallel()
	for i in count:
		var band := bands[i]
		_tween.tween_property(band, "position:y", view_size.y * 0.25, duration).set_delay(stagger * i) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_property(band, "modulate:a", 0.0, duration).set_delay(stagger * i) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(_clear)
	return true


## Stops a wipe in flight and removes it.
func finish() -> void:
	if _tween != null:
		_tween.kill()
	_clear()


func _clear() -> void:
	for band in bands:
		if is_instance_valid(band):
			band.queue_free()
	bands.clear()
