class_name ActionTile
extends SkillCard
## A skill as a compact action tile for a dock, the way Into the Breach shows
## a mech's weapons: a big icon, the short name under it (text always on
## actions), the Energy cost in the corner and its hotkey in the other. The
## effect is kept for the tooltip and the focused card (FocusCard), not drawn.
## It is a SkillCard, so set_skill, set_problem, disabled and pressed work
## the same.
##
##   var t := ActionTile.make_tile("Beam", 3, "Deal 12. Pierce 20%.", "+2", "intent_attack", 1)

var icon_id := ""
var hotkey := 0
var icon_rect: TextureRect
var hotkey_label: Label


static func make_tile(p_name: String, p_cost: int, p_effect: String, p_rank := "", p_icon := "intent_attack", p_hotkey := 0) -> ActionTile:
	var t := ActionTile.new()
	t.icon_id = p_icon
	t.hotkey = p_hotkey
	t._tile()
	t.set_skill(p_name, p_cost, p_effect, p_rank)
	return t


func _tile() -> void:
	custom_minimum_size = UiIcons.kit_vector("action_tile.size", Vector2(112, 104))
	effect_label.visible = false
	name_label.max_lines_visible = 2
	name_label.add_theme_font_size_override("font_size", PixelTheme.font_size("body"))
	var face: VBoxContainer = get_node("Face")
	icon_rect = TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.texture = UiIcons.texture(icon_id)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.custom_minimum_size = UiIcons.icon_size()
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(icon_rect)
	face.move_child(icon_rect, 1)
	hotkey_label = Label.new()
	hotkey_label.name = "Hotkey"
	hotkey_label.text = str(hotkey) if hotkey > 0 else ""
	hotkey_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotkey_label.add_theme_color_override("font_color", UiStyle.role("text_quiet"))
	# The hotkey takes the rank's corner; the rank moves into the name.
	var top: HBoxContainer = face.get_child(0)
	top.add_child(hotkey_label)


func set_skill(p_name: String, p_cost: int, p_effect: String, p_rank := "") -> void:
	super.set_skill(p_name, p_cost, p_effect, p_rank)
	if hotkey_label != null:
		rank_label.visible = false
		name_label.text = skill_name if rank.is_empty() else "%s %s" % [skill_name, rank]


func set_icon(p_icon: String) -> void:
	icon_id = p_icon
	icon_rect.texture = UiIcons.texture(icon_id)
