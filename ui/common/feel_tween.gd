class_name FeelTween
extends RefCounted
## Named tween presets from data/feel/feel.json "tweens", so every screen uses
## the same timing and easing. Durations follow the animation speed setting
## (0 when animations are skipped); with reduced motion, overshooting easings
## (back, elastic, bounce) are swapped for a plain one.
##
##     FeelTween.to(panel, "modulate:a", 1.0, "ui")
##     var t := create_tween()
##     FeelTween.step(t, unit, "position", hit_spot, "attack_strike")

const TRANSITIONS := {
	"linear": Tween.TRANS_LINEAR, "sine": Tween.TRANS_SINE, "quad": Tween.TRANS_QUAD,
	"cubic": Tween.TRANS_CUBIC, "quart": Tween.TRANS_QUART, "quint": Tween.TRANS_QUINT,
	"expo": Tween.TRANS_EXPO, "circ": Tween.TRANS_CIRC, "back": Tween.TRANS_BACK,
	"elastic": Tween.TRANS_ELASTIC, "bounce": Tween.TRANS_BOUNCE, "spring": Tween.TRANS_SPRING,
}
const EASES := {
	"in": Tween.EASE_IN, "out": Tween.EASE_OUT, "in_out": Tween.EASE_IN_OUT, "out_in": Tween.EASE_OUT_IN,
}
const OVERSHOOTING := ["back", "elastic", "bounce", "spring"]


static func preset(name: String) -> Dictionary:
	var tweens: Dictionary = FeelData.feel().get("tweens", {})
	if not tweens.has(name):
		push_warning("FeelTween: no preset '%s'" % name)
		return {"ms": 160, "trans": "quad", "ease": "out"}
	return tweens[name]


static func names() -> Array:
	return FeelData.feel().get("tweens", {}).keys()


## The preset's duration in seconds, after the animation speed setting.
static func seconds(name: String, settings: GameSettings = null) -> float:
	settings = settings if settings else GameSettings.shared()
	return settings.scale_seconds(float(preset(name)["ms"]) / 1000.0)


static func transition(name: String, settings: GameSettings = null) -> Tween.TransitionType:
	settings = settings if settings else GameSettings.shared()
	var trans: String = preset(name).get("trans", "quad")
	if settings.reduced_motion and trans in OVERSHOOTING:
		trans = "quad"
	return TRANSITIONS.get(trans, Tween.TRANS_QUAD)


static func easing(name: String) -> Tween.EaseType:
	return EASES.get(preset(name).get("ease", "out"), Tween.EASE_OUT)


## Value of the preset's curve at `elapsed` seconds, for code that animates by hand.
static func sample(name: String, from: Variant, to: Variant, elapsed: float, settings: GameSettings = null) -> Variant:
	var duration := seconds(name, settings)
	if duration <= 0.0 or elapsed >= duration:
		return to
	return Tween.interpolate_value(from, to - from, elapsed, duration, transition(name, settings), easing(name))


## Tweens one property with a preset and returns the new Tween.
static func to(node: Node, property: NodePath, value: Variant, name: String, settings: GameSettings = null) -> Tween:
	var tween := node.create_tween()
	step(tween, node, property, value, name, settings)
	return tween


## Adds one preset step to an existing tween (for sequences).
static func step(tween: Tween, node: Object, property: NodePath, value: Variant, name: String, settings: GameSettings = null) -> PropertyTweener:
	return tween.tween_property(node, property, value, seconds(name, settings)) \
		.set_trans(transition(name, settings)).set_ease(easing(name))
