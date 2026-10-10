class_name NumberPopup
extends Node2D
## A number that pops out of a unit when its health or energy changes: it pops
## in, holds, rises and fades (data/feel/feel.json "popup"). The kind is shown
## by sign, icon and color together, never color alone:
##   damage  "-12"        red-orange, no icon
##   crit    "-30!"       gold, larger pop
##   heal    "+8"  cross  green
##   energy  "+3 EN" bolt blue ("-3 EN" when spent)
## With reduced motion the number fades in place without rising or popping.

const KINDS := ["damage", "crit", "heal", "energy"]
const HEAL_ICON := preload("res://assets/ui/icons/popup_heal.png")
const ENERGY_ICON := preload("res://assets/ui/icons/popup_energy.png")

static var _spawned := 0

var amount := 0
var kind := "damage"
var settings: GameSettings
var text := ""
var font: Font
var font_size := 20
var color := Color.WHITE
var icon: Texture2D


## Adds a popup to `parent` at `at` and starts it. It frees itself when done.
static func spawn(parent: Node, at: Vector2, p_amount: int, p_kind := "damage", p_settings: GameSettings = null) -> NumberPopup:
	var popup := NumberPopup.new()
	popup.setup(p_amount, p_kind, p_settings)
	# Fan successive popups left, centre, right so a burst stays readable.
	var spread := FeelData.number("popup.spread_px", 6.0)
	popup.position = at + Vector2(((_spawned % 3) - 1) * spread, 0)
	_spawned += 1
	parent.add_child(popup)
	return popup


static func text_for(value: int, p_kind: String) -> String:
	match p_kind:
		"heal":
			return "+%d" % absi(value)
		"energy":
			return ("+%d EN" if value >= 0 else "-%d EN") % absi(value)
		"crit":
			return "-%d!" % absi(value)
		_:
			return "-%d" % absi(value)


static func color_for(p_kind: String) -> Color:
	return FeelData.color("popup_" + (p_kind if p_kind in KINDS else "damage"))


static func icon_for(p_kind: String) -> Texture2D:
	match p_kind:
		"heal":
			return HEAL_ICON
		"energy":
			return ENERGY_ICON
	return null


func setup(p_amount: int, p_kind: String, p_settings: GameSettings = null) -> void:
	amount = p_amount
	kind = p_kind if p_kind in KINDS else "damage"
	settings = p_settings
	text = text_for(amount, kind)
	color = color_for(kind)
	icon = icon_for(kind)
	font = PixelTheme.font()
	font_size = int(FeelData.number("popup.font_size", 20))
	z_index = 100


func _ready() -> void:
	_animate()


## Total time on screen in seconds, after the animation speed setting.
func lifetime() -> float:
	var s := _settings()
	var ms := FeelData.number("popup.pop_ms") + FeelData.number("popup.hold_ms") + FeelData.number("popup.fade_ms")
	return s.scale_seconds(ms / 1000.0)


func _animate() -> void:
	var s := _settings()
	if s.skips_animations():
		queue_free()
		return
	var reduced := s.reduced_motion
	var pop_scale := FeelData.number("reduced_motion.pop_scale", 1.0) if reduced else FeelData.number("popup.pop_scale", 1.3)
	if kind == "crit" and not reduced:
		pop_scale *= 1.25
	var rise := FeelData.number("reduced_motion.popup_rise_px", 0.0) if reduced else FeelData.number("popup.rise_px", 20.0)
	var pop := s.scale_seconds(FeelData.number("popup.pop_ms") / 1000.0)
	var hold := s.scale_seconds(FeelData.number("popup.hold_ms") / 1000.0)
	var fade := s.scale_seconds(FeelData.number("popup.fade_ms") / 1000.0)
	scale = Vector2.ONE * pop_scale
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, pop).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold)
	tween.tween_property(self, "modulate:a", 0.0, fade)
	if rise > 0.0:
		var move := create_tween()
		move.tween_property(self, "position:y", position.y - rise, pop + hold + fade) \
			.set_trans(FeelTween.transition("popup_rise", s)).set_ease(FeelTween.easing("popup_rise"))
	tween.tween_callback(queue_free)


func _draw() -> void:
	var outline := FeelData.color("popup_outline")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var icon_w := 0.0
	if icon:
		icon_w = icon.get_width() * 2 + 4
	var left := roundf(-(width + icon_w) / 2.0)
	var baseline := roundf(font.get_ascent(font_size) / 2.0)
	if icon:
		var size := icon.get_size() * 2
		draw_texture_rect(icon, Rect2(Vector2(left, roundf(-size.y / 2.0)), size), false)
	var at := Vector2(left + icon_w, baseline)
	# Bitmap fonts have no outline, so the outline is the text drawn four times
	# one font pixel off.
	var px := maxf(1.0, roundf(font_size / 10.0))
	for offset: Vector2 in [Vector2(-px, 0), Vector2(px, 0), Vector2(0, -px), Vector2(0, px)]:
		draw_string(font, at + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _settings() -> GameSettings:
	return settings if settings else GameSettings.shared()
