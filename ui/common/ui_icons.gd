class_name UiIcons
extends RefCounted
## The icon library: icon ids -> texture, name, color and tooltip lines, read
## from data/ui/icons.json. Screens name icons by id, never by path.
##
##   UiIcons.texture("atk"), UiIcons.display_name("atk"), UiIcons.color("atk")
##
## Layout numbers for the kit widgets come from data/ui/ui_kit.json:
##   UiIcons.kit("tooltip.delay_seconds", 0.35)

const ICONS_PATH := "res://data/ui/icons.json"
const KIT_PATH := "res://data/ui/ui_kit.json"
const FALLBACK_ID := "unknown"

static var _textures := {}
static var _scaled := {}


static func table() -> Dictionary:
	return FeelData.table(ICONS_PATH).get("icons", {})


static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in table():
		out.append(id)
	return out


static func has(id: String) -> bool:
	return table().has(id)


## The icon's texture; an unknown id gets the "unknown" icon and a warning.
static func texture(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var entry := _entry(id)
	var path := str(entry.get("texture", ""))
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if tex == null and id != FALLBACK_ID:
		push_warning("UiIcons: no texture for '%s'" % id)
		tex = texture(FALLBACK_ID)
	_textures[id] = tex
	return tex


static func display_name(id: String) -> String:
	return str(_entry(id).get("name", id.capitalize()))


## The one or two plain lines a tooltip shows for this icon.
static func text(id: String) -> String:
	return str(_entry(id).get("text", ""))


static func color(id: String) -> Color:
	return FeelData.color(str(_entry(id).get("color", "text")))


## A number or array from ui_kit.json at a dotted path such as "tooltip.width".
static func kit(path: String, fallback: Variant = 0) -> Variant:
	var node: Variant = FeelData.table(KIT_PATH)
	for key in path.split("."):
		if not (node is Dictionary) or not node.has(key):
			return fallback
		node = node[key]
	return node


static func kit_vector(path: String, fallback := Vector2.ZERO) -> Vector2:
	var v: Variant = kit(path, null)
	if v is Array and v.size() == 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback


## Icon size on screen: the 12 px art at the kit's whole-number scale.
static func icon_size() -> Vector2:
	return Vector2(12, 12) * int(kit("icon_scale", 2))


## The icon scaled to the kit size with crisp pixels, for a Button's `icon`
## (which draws its texture at its own size).
static func scaled_texture(id: String) -> Texture2D:
	if _scaled.has(id):
		return _scaled[id]
	var tex := texture(id)
	var out: Texture2D = tex
	if tex != null:
		var img := tex.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			var n := int(kit("icon_scale", 2))
			img.resize(img.get_width() * n, img.get_height() * n, Image.INTERPOLATE_NEAREST)
			out = ImageTexture.create_from_image(img)
	_scaled[id] = out
	return out


## A TextureRect showing the icon at the kit size, ignoring the mouse.
static func rect(id: String) -> TextureRect:
	var r := TextureRect.new()
	r.name = "Icon"
	r.texture = texture(id)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = icon_size()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _entry(id: String) -> Dictionary:
	var t := table()
	if t.has(id):
		return t[id]
	return t.get(FALLBACK_ID, {})
