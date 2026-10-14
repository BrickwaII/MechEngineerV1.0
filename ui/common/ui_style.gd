class_name UiStyle
extends RefCounted
## The design system's shared rules as code: spacing on the 8 px grid, the
## three panel styles, color roles and text sizes. Numbers and colors come
## from data/ui/ui_kit.json; the rules themselves are in ui/README.md.
##
##   box.add_theme_constant_override("separation", UiStyle.space("s"))
##   panel.add_theme_stylebox_override("panel", UiStyle.panel("plain"))
##   label.add_theme_color_override("font_color", UiStyle.role("bad"))
##   UiStyle.caption(label)   # the only small text: a caption over a group

## The three panel styles. Borders only on things you can click.
const PANELS: Array[String] = ["plain", "card", "overlay"]


## A spacing step in pixels: xs 4 (inside one control), s 8, m 16, l 24, xl 32.
static func space(step := "s") -> int:
	return int(UiIcons.kit("space.%s" % step, grid()))


## The grid every gap and size snaps to.
static func grid() -> int:
	return int(UiIcons.kit("grid", 8))


## Every spacing value the kit allows.
static func spaces() -> Array[int]:
	var out: Array[int] = [0]
	var table: Variant = UiIcons.kit("space", {})
	if table is Dictionary:
		for k: String in table:
			out.append(int(table[k]))
	return out


## The color for a role: text, text_quiet, title, interactive, good, bad,
## caution, info, ally, enemy, rare, hint, neutral. An unknown role is "text".
static func role(name: String) -> Color:
	return FeelData.color(role_palette_name(name))


static func role_palette_name(name: String) -> String:
	var table: Variant = UiIcons.kit("color_roles", {})
	if table is Dictionary and table.has(name):
		return str(table[name])
	return "text"


static func roles() -> Array[String]:
	var out: Array[String] = []
	var table: Variant = UiIcons.kit("color_roles", {})
	if table is Dictionary:
		for k: String in table:
			out.append(k)
	return out


## One of the three panel styles as a flat box:
##   plain    information on a plain background, no border
##   card     something you can click or open: a border, brighter on hover
##   overlay  floats above the screen (modal, drawer): a border and a shadow
## `hover` gives a card's hover look.
static func panel(kind := "plain", hover := false) -> StyleBoxFlat:
	if not kind in PANELS:
		push_warning("UiStyle: no panel style '%s'" % kind)
		kind = "plain"
	var spec: Dictionary = UiIcons.kit("panels.%s" % kind, {})
	var box := StyleBoxFlat.new()
	box.anti_aliasing = false
	box.bg_color = FeelData.color(str(spec.get("fill", "panel")))
	var border := str(spec.get("border_hover" if hover and spec.has("border_hover") else "border", ""))
	if not border.is_empty():
		box.border_color = FeelData.color(border)
		box.set_border_width_all(2)
	var shadow := int(spec.get("shadow", 0))
	if shadow > 0:
		box.shadow_color = Color(0, 0, 0, 0.5)
		box.shadow_size = shadow
	box.set_content_margin_all(int(spec.get("padding", space("s"))))
	return box


## True when a panel style draws a border (only things you can click).
static func has_border(kind: String) -> bool:
	return not str(UiIcons.kit("panels.%s.border" % kind, "")).is_empty()


## The smallest text size anything the player needs may use.
static func min_text_size() -> int:
	return PixelTheme.font_size(str(UiIcons.kit("text.min_size", "body")))


## Styles `label` as a caption: the one use of small text, a short heading
## over a group whose contents carry their own full-size text.
static func caption(label: Label) -> Label:
	label.theme_type_variation = &"SmallLabel"
	label.set_meta(&"ui_caption", true)
	return label


static func is_caption(control: Control) -> bool:
	return control.get_meta(&"ui_caption", false)


## A fixed gap of `step` (a spacer in a box).
static func gap(step := "s") -> Control:
	var c := Control.new()
	c.name = "Gap"
	c.custom_minimum_size = Vector2(space(step), space(step))
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A gap that takes the free space in a box.
static func spring() -> Control:
	var c := Control.new()
	c.name = "Spring"
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## An HBox or VBox with a grid gap.
static func row(step := "s") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", space(step))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func column(step := "s") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", space(step))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


## A label in a color role at body size (or "title").
static func label(text: String, color_role := "text", size := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", role(color_role))
	if size != "body":
		l.add_theme_font_size_override("font_size", PixelTheme.font_size(size))
	return l


## The tint of act `act` (0 for act 1): its color from data/ui/ui_kit.json
## "acts" (the demo picker's act colors).
static func act_tint(act: int) -> Color:
	var tints: Array = UiIcons.kit("acts.tints", ["ally"])
	return FeelData.color(str(tints[clampi(act, 0, tints.size() - 1)]))


## `base` with act `act`'s tint mixed in by the kit's share for `what`
## ("background" or "panel").
static func act_tinted(base: Color, act: int, what := "background") -> Color:
	return base.lerp(act_tint(act), float(UiIcons.kit("acts.%s_share" % what, 0.05)))


## The icon id of act `act`'s emblem.
static func act_emblem(act: int) -> String:
	var emblems: Array = UiIcons.kit("acts.emblems", ["demo_map"])
	return str(emblems[clampi(act, 0, emblems.size() - 1)])
