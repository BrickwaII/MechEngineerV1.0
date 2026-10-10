class_name EnemyLineup
extends Control
## Dev preview of the enemy factions: every unit type grouped by faction, in
## all three tiers, playing its idle animation. Factions, unit types and tier
## names come from data/combat/factions.json and enemy_tables.json; the
## sprites from data/feel/sprite_manifest.json.

const BLOCK := Vector2(620, 370)
const ORIGIN := Vector2(24, 64)
const LABEL_WIDTH := 100.0
const CELL := Vector2(170, 108)

var factions: FactionTable
var enemy_table: EnemyTable
## Every sprite on screen, faction by faction, unit by unit, weakest tier first.
var sprites: Array[UnitSprite] = []


func _ready() -> void:
	theme = PixelTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	enemy_table = EnemyTable.load_default()
	factions = enemy_table.factions
	var back := ColorRect.new()
	back.color = FeelData.color("background")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_label("Enemy factions: every unit in every tier", Vector2(24, 16), "TitleLabel")
	var ids: Array = factions.factions.keys()
	for i in ids.size():
		var at := ORIGIN + Vector2((i % 2) * BLOCK.x, (i / 2) * BLOCK.y)
		_faction_block(ids[i], at)


func _faction_block(faction: String, at: Vector2) -> void:
	var color := factions.faction_color(faction)
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.position = at + Vector2(0, 6)
	swatch.size = Vector2(14, 14)
	add_child(swatch)
	var title := _label(factions.faction_name(faction), at + Vector2(22, 0), "")
	title.add_theme_color_override("font_color", color)
	_label(str(factions.factions[faction].get("description", "")), at + Vector2(22, 22), "SmallLabel")
	var units: Array = factions.factions[faction].get("units", [])
	for r in factions.tiers.size():
		var tier: String = factions.tiers[r]
		var y := at.y + 44 + r * CELL.y
		_label(tier.capitalize(), Vector2(at.x, y + 40), "DimLabel")
		for c in units.size():
			var id := FactionTable.enemy_id(str(units[c].unit), tier)
			var look := enemy_table.sprite_of(id)
			var x := at.x + LABEL_WIDTH + c * CELL.x
			var sprite := UnitSprite.new()
			sprite.setup(look.get("unit", ""), look.get("tier", tier))
			sprite.position = Vector2(x + CELL.x / 2, y + 44)
			add_child(sprite)
			sprites.append(sprite)
			var name_label := _label(enemy_table.name_of(id), Vector2(x, y + 88), "SmallLabel")
			name_label.size.x = CELL.x
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Holds every sprite on one idle frame (for screenshots).
func freeze_on(frame: int) -> void:
	for sprite in sprites:
		sprite.show_frame(&"idle", frame)


func _label(text: String, at: Vector2, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.theme_type_variation = variation
	add_child(label)
	return label
