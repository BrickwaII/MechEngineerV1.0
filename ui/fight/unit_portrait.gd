class_name UnitPortrait
extends Control
## A unit's still portrait in a small frame: the battle sprite standing still,
## scaled to `side` pixels, on a tile edged in its side's color. The turn
## order and the action dock show units this way; the name is in the tooltip.
##
##   var p := UnitPortrait.make(look, true, 40)

var look := {}
var is_enemy := false
var side := 40.0
var now := false:
	set(v):
		now = v
		queue_redraw()
var sprite: BattleUnitSprite


static func make(p_look: Dictionary, p_is_enemy: bool, p_side := 40.0) -> UnitPortrait:
	var p := UnitPortrait.new()
	p.look = p_look
	p.is_enemy = p_is_enemy
	p.side = p_side
	p._build()
	return p


func _build() -> void:
	name = "Portrait"
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	sprite = BattleUnitSprite.new()
	sprite.name = "Sprite"
	add_child(sprite)
	sprite.setup_look(look)
	# The battle sprites are 32 px frames drawn at the manifest's scale; fit
	# the frame to the tile.
	var frame := float(SpriteManifest.frame_size(str(look.get("unit_id", ""))).x)
	sprite.scale = Vector2.ONE * side / maxf(frame, 1.0)
	if not is_enemy:
		sprite.scale.x = absf(sprite.scale.x)
	sprite.position = Vector2(side, side) / 2.0
	sprite.set_still(true)


func _draw() -> void:
	var edge := FeelData.color("active") if now else FeelData.color("enemy" if is_enemy else "ally").darkened(0.15)
	draw_rect(Rect2(Vector2.ZERO, size), FeelData.color("enemy" if is_enemy else "ally").darkened(0.7))
	draw_rect(Rect2(Vector2.ZERO, size), edge, false, 3.0 if now else 2.0)
