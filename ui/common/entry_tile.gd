class_name EntryTile
extends Button
## A big entry tile with art, the way a homepage starts you off: the art on
## top (nothing over it), the title, and one line under it. It is a Button,
## so disabled, pressed and tooltips work as usual.
##
##   var t := EntryTile.make("New Run", "Draft a squad and take the city.", art)
##   EntryTile.icon_art("demo_boss")   # an icon drawn large as the art

var title_label: Label
var line_label: Label
var art: Control
## Extra content under the line (a row of icons, for example).
var extra: VBoxContainer


static func make(p_title: String, p_line: String, p_art: Control) -> EntryTile:
	var t := EntryTile.new()
	t._build(p_title, p_line, p_art)
	return t


## An icon from icons.json drawn large, for a tile's art.
static func icon_art(id: String, scale := 6) -> Control:
	var r := TextureRect.new()
	r.name = "Art"
	r.texture = UiIcons.texture(id)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.custom_minimum_size = Vector2(12, 12) * scale
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _build(p_title: String, p_line: String, p_art: Control) -> void:
	name = "Tile_%s" % p_title.to_pascal_case()
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = UiIcons.kit_vector("entry_tile.size", Vector2(240, 232))
	clip_contents = true
	var col := UiStyle.column("s")
	col.name = "Face"
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := float(UiStyle.space("m"))
	col.offset_left = pad
	col.offset_top = pad
	col.offset_right = -pad
	col.offset_bottom = -pad
	add_child(col)
	art = p_art
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var stage := CenterContainer.new()
	stage.name = "Stage"
	stage.custom_minimum_size.y = UiIcons.kit_vector("entry_tile.size", Vector2(240, 232)).y * 0.42
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(art)
	col.add_child(stage)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = p_title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_size_override("font_size", PixelTheme.font_size("title"))
	UiTooltip._bold(title_label, UiStyle.role("title"))
	col.add_child(title_label)
	line_label = Label.new()
	line_label.name = "Line"
	line_label.text = p_line
	line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_label.add_theme_color_override("font_color", UiStyle.role("text_quiet"))
	col.add_child(line_label)
	extra = UiStyle.column("xs")
	extra.name = "Extra"
	col.add_child(extra)


func set_line(text: String) -> void:
	line_label.text = text
