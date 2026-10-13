class_name StatStrip
extends VBoxContainer
## The three headline stats of a card, each with its own kind of graphic so
## they read at a glance without labels (as EDHREC's cards do):
##
##   bar     a meter with "38/50" beside it          (HP, Energy)
##   number  one big number                          (ATK, a count)
##   ring    a ring gauge with the percent beside it (odds, a share)
##   arrow   an up or down arrow with "×1.5"         (a multiplier)
##   pips    filled and empty pips                   (defense level)
##   chip    a short word in a box                   (next turn: "2nd")
##
##   var strip := StatStrip.make([
##       StatStrip.bar("hp", 38, 50),
##       StatStrip.number("atk", 12, "", [UiFormula.parse("{Base} + {Rank}", {"Base": 10, "Rank": 2}, 12)]),
##       StatStrip.ring("odds", 0.62),
##   ])
##   strip.set_stat(0, StatStrip.bar("hp", 30, 50))   # the bar animates
##
## Any spec may also carry "numbers" (the tooltip's numbers line) and
## "title" (its name), to say more than the icon's own; "show_icon": false
## hides the icon where the graphic says enough; a bar takes "bar_size";
## "text" replaces the words beside the graphic (a ring still estimating: "...").
##
## `stacked` puts the first headline on its own full-width row (a long bar)
## and the other two beneath it, for narrow cards.
##
## A strip holds exactly three, each of a different kind. Every headline has
## the standard tooltip; `math` lines explain how its number came about.
## Everything else about the card goes in its DetailModal.

const KINDS: Array[String] = ["bar", "number", "ring", "arrow", "pips", "chip"]
const COUNT := 3

var headlines: Array[StatStrip.Headline] = []
## The first headline alone on a full-width row, the others under it.
var stacked := false:
	set(v):
		stacked = v
		_place()

var _rows: Array[HBoxContainer] = []


## A strip of three headline stats from specs made by bar(), number(), ...
static func make(specs: Array) -> StatStrip:
	var s := StatStrip.new()
	s.set_stats(specs)
	return s


## A meter: `value` of `max_value`. `meter` is a GhostBar kind: "hp" or "energy".
## A screen that animates its own meter passes it as spec["meter_node"] (and
## a thin second meter as spec["sub_node"]); the headline then only shows it.
static func bar(icon: String, value: float, max_value: float, tip := "", math: Array = [], meter := "hp") -> Dictionary:
	return {"kind": "bar", "icon": icon, "value": value, "max": max_value, "tip": tip, "math": math, "meter": meter}


## One big number (or short text such as "?").
static func number(icon: String, value: Variant, tip := "", math: Array = [], color_role := "title") -> Dictionary:
	return {"kind": "number", "icon": icon, "value": value, "tip": tip, "math": math, "role": color_role}


## A ring gauge: `share` from 0 to 1, shown as a percent beside it.
static func ring(icon: String, share: float, tip := "", math: Array = [], color_role := "hint") -> Dictionary:
	return {"kind": "ring", "icon": icon, "value": clampf(share, 0.0, 1.0), "tip": tip, "math": math, "role": color_role}


## A multiplier: an up arrow above 1, a down arrow below it.
static func arrow(icon: String, multiplier: float, tip := "", math: Array = []) -> Dictionary:
	return {"kind": "arrow", "icon": icon, "value": multiplier, "tip": tip, "math": math}


## Pips: `value` filled of `max_value`.
static func pips(icon: String, value: int, max_value: int, tip := "", math: Array = [], color_role := "info") -> Dictionary:
	return {"kind": "pips", "icon": icon, "value": value, "max": max_value, "tip": tip, "math": math, "role": color_role}


## A short word in a box, such as a turn position.
static func chip(icon: String, text: String, tip := "", math: Array = [], color_role := "hint") -> Dictionary:
	return {"kind": "chip", "icon": icon, "value": text, "tip": tip, "math": math, "role": color_role}


func _init() -> void:
	name = "StatStrip"
	add_theme_constant_override("separation", UiStyle.space("xs"))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		var r := HBoxContainer.new()
		r.name = "Row%d" % i
		r.add_theme_constant_override("separation", UiStyle.space("m"))
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		_rows.append(r)


## The gap between headlines on a row.
func set_gap(px: int) -> void:
	for r in _rows:
		r.add_theme_constant_override("separation", px)


func set_stats(specs: Array) -> void:
	if specs.size() != COUNT:
		push_warning("StatStrip: %d stats; a card shows exactly %d" % [specs.size(), COUNT])
	var kinds := {}
	for spec: Dictionary in specs:
		if kinds.has(spec["kind"]):
			push_warning("StatStrip: two '%s' stats; each headline needs its own graphic" % spec["kind"])
		kinds[spec["kind"]] = true
	for h in headlines:
		h.get_parent().remove_child(h)
		h.queue_free()
	headlines.clear()
	for i in specs.size():
		var h := StatStrip.Headline.new()
		h.name = "Stat%d" % i
		_rows[0].add_child(h)
		headlines.append(h)
		h.set_spec(specs[i])
	_place()


func _place() -> void:
	if _rows.is_empty():
		return
	for i in headlines.size():
		var want := _rows[1] if stacked and i > 0 else _rows[0]
		var h := headlines[i]
		if h.get_parent() != want:
			h.get_parent().remove_child(h)
			want.add_child(h)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL if stacked and i == 0 else Control.SIZE_FILL
	_rows[1].visible = stacked and headlines.size() > 1


## Changes one headline; a bar of the same kind animates to the new value.
func set_stat(index: int, spec: Dictionary) -> void:
	headlines[index].set_spec(spec)


func headline(index: int) -> StatStrip.Headline:
	return headlines[index]


## The kinds in order, e.g. ["bar", "number", "ring"].
func kinds() -> Array[String]:
	var out: Array[String] = []
	for h in headlines:
		out.append(str(h.spec.get("kind", "")))
	return out


## One headline stat: its icon, its graphic and its text, with a tooltip.
class Headline:
	extends HBoxContainer

	var spec: Dictionary = {}
	var icon_rect: TextureRect
	var meter: GhostBar
	var gauge: StatStrip.StatGauge
	var value_label: Label

	func _init() -> void:
		add_theme_constant_override("separation", UiStyle.space("xs"))
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_spec(p_spec: Dictionary) -> void:
		var same_bar: bool = meter != null and spec.get("kind") == "bar" and p_spec["kind"] == "bar" \
			and spec.get("meter") == p_spec.get("meter")
		var old := spec
		spec = p_spec
		if same_bar and spec.has("meter_node"):
			value_label.text = text()
			_retip()
			return
		if same_bar:
			if not is_equal_approx(float(old["max"]), float(spec["max"])):
				meter.reset(meter.value, float(spec["max"]))
			meter.set_value(float(spec["value"]))
			value_label.text = text()
			_retip()
			return
		for keep: Variant in [p_spec.get("meter_node"), p_spec.get("sub_node")]:
			if keep is Node and (keep as Node).get_parent() != null:
				(keep as Node).get_parent().remove_child(keep)
		for c in get_children():
			remove_child(c)
			c.queue_free()
		meter = null
		gauge = null
		icon_rect = UiIcons.rect(str(spec["icon"]))
		# A cramped card may drop the icon when its graphic says enough (a green
		# HP bar); the tooltip still names it.
		icon_rect.visible = spec.get("show_icon", true)
		add_child(icon_rect)
		value_label = Label.new()
		value_label.name = "Value"
		value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.add_theme_color_override("font_color", UiStyle.role("title"))
		match str(spec["kind"]):
			"bar":
				# A screen may hand in its own meter (a GhostBar subclass with
				# previews) and a thin second meter under it (Energy under HP).
				meter = spec.get("meter_node") if spec.get("meter_node") is GhostBar else GhostBar.new()
				meter.name = "Meter"
				meter.kind = str(spec.get("meter", "hp"))
				meter.custom_minimum_size = spec.get("bar_size", UiIcons.kit_vector("stat_strip.bar_size", Vector2(64, 10)))
				meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var stack := VBoxContainer.new()
				stack.name = "Meters"
				stack.add_theme_constant_override("separation", 0)
				stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if meter.get_parent() != null:
					meter.get_parent().remove_child(meter)
				stack.add_child(meter)
				var sub: Variant = spec.get("sub_node")
				if sub is Control:
					var sub_control := sub as Control
					if sub_control.get_parent() != null:
						sub_control.get_parent().remove_child(sub_control)
					sub_control.name = "SubMeter"
					sub_control.custom_minimum_size.y = float(UiIcons.kit("stat_strip.sub_bar_height", 6))
					stack.add_child(sub_control)
				add_child(stack)
				if not spec.has("meter_node"):
					meter.reset(float(spec["value"]), float(spec["max"]))
			"number":
				value_label.add_theme_font_size_override("font_size", PixelTheme.font_size("title"))
				value_label.add_theme_color_override("font_color", UiStyle.role(str(spec.get("role", "title"))))
			"ring", "pips", "arrow":
				gauge = StatStrip.StatGauge.new()
				gauge.name = "Gauge"
				gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				add_child(gauge)
				gauge.setup(spec)
				if spec["kind"] == "arrow":
					value_label.add_theme_color_override("font_color", gauge.color)
			"chip":
				var box := StyleBoxFlat.new()
				box.bg_color = FeelData.color("bar_back")
				box.border_color = UiStyle.role(str(spec.get("role", "hint")))
				box.set_border_width_all(1)
				box.content_margin_left = UiStyle.space("xs")
				box.content_margin_right = UiStyle.space("xs")
				value_label.add_theme_stylebox_override("normal", box)
				value_label.add_theme_color_override("font_color", UiStyle.role(str(spec.get("role", "hint"))))
		value_label.text = text()
		value_label.visible = not value_label.text.is_empty()
		add_child(value_label)
		_retip()

	## The text beside the graphic: "38/50", "12", "62%", "×1.5", "2/5", "2nd".
	func text() -> String:
		if spec.has("text"):
			return str(spec["text"])
		var v: Variant = spec.get("value")
		match str(spec.get("kind")):
			"bar":
				return "%s/%s" % [UiFormula.fmt(v), UiFormula.fmt(spec["max"])]
			"ring":
				return "%d%%" % roundi(float(v) * 100.0)
			"arrow":
				return "×%s" % UiFormula.fmt(float(v))
			"pips":
				return ""
		return UiFormula.fmt(v)

	func _retip() -> void:
		var icon := str(spec["icon"])
		var lines := str(spec.get("tip", ""))
		if lines.is_empty():
			lines = UiIcons.text(icon)
		var shown := text()
		if spec.get("kind") == "pips":
			shown = "%s/%s" % [spec["value"], spec["max"]]
		var numbers := str(spec.get("numbers", "%s: %s" % [UiIcons.display_name(icon), shown]))
		UiTooltip.attach(self, str(spec.get("title", UiIcons.display_name(icon))), lines, numbers, icon, spec.get("math", []))


## The drawn graphic of a ring, pips or arrow headline.
class StatGauge:
	extends Control

	var kind := "ring"
	var value := 0.0
	var max_value := 1.0
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(spec: Dictionary) -> void:
		kind = str(spec["kind"])
		value = float(spec["value"])
		max_value = float(spec.get("max", 1.0))
		match kind:
			"ring":
				color = UiStyle.role(str(spec.get("role", "hint")))
				var d := float(UiIcons.kit("stat_strip.ring_size", 28))
				custom_minimum_size = Vector2(d, d)
			"pips":
				color = UiStyle.role(str(spec.get("role", "info")))
				var pip := UiIcons.kit_vector("stat_strip.pip_size", Vector2(6, 10))
				var n := maxi(1, int(max_value))
				custom_minimum_size = Vector2(n * pip.x + (n - 1) * 2, pip.y)
			"arrow":
				var up := value >= 1.0
				color = UiStyle.role(str(UiIcons.kit("stat_strip.arrow_up_role" if up else "stat_strip.arrow_down_role", "good")))
				if is_equal_approx(value, 1.0):
					color = UiStyle.role("text_quiet")
				custom_minimum_size = Vector2(12, 16)
		queue_redraw()

	func _draw() -> void:
		match kind:
			"ring":
				var r := floorf(size.x / 2.0)
				var w := float(UiIcons.kit("stat_strip.ring_width", 4))
				var c := (size / 2.0).floor()
				var mid := r - w / 2.0
				draw_circle(c, r, FeelData.color("panel_border"), true, -1.0, false)
				draw_circle(c, r - 1.0, FeelData.color("bar_back"), true, -1.0, false)
				if value > 0.0:
					draw_arc(c, mid - 0.5, -PI / 2.0, -PI / 2.0 + TAU * value, 64, color, w - 2.0, false)
				draw_circle(c, r - w, FeelData.color("panel_border"), true, -1.0, false)
				draw_circle(c, r - w - 1.0, FeelData.color("panel"), true, -1.0, false)
			"pips":
				var pip := UiIcons.kit_vector("stat_strip.pip_size", Vector2(6, 10))
				for i in int(max_value):
					var rect := Rect2(Vector2(i * (pip.x + 2), 0), pip)
					draw_rect(rect, FeelData.color("panel_border"))
					draw_rect(rect.grow(-1), color if i < int(value) else FeelData.color("bar_back"))
			"arrow":
				var up := value >= 1.0
				var mid := size.x / 2.0
				var h := size.y
				# A pixel arrow: a 2 px shaft and a 6 px wide head.
				var head := PackedVector2Array([Vector2(mid, 0), Vector2(mid + 5, 6), Vector2(mid - 5, 6)]) if up \
					else PackedVector2Array([Vector2(mid, h), Vector2(mid + 5, h - 6), Vector2(mid - 5, h - 6)])
				if is_equal_approx(value, 1.0):
					draw_rect(Rect2(0, h / 2.0 - 1, size.x, 2), color)
					return
				draw_colored_polygon(head, color)
				var shaft := Rect2(mid - 1, 6, 2, h - 6) if up else Rect2(mid - 1, 0, 2, h - 6)
				draw_rect(shaft, color)
