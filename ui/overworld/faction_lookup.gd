class_name FactionLookup
extends RefCounted
## Which enemy faction holds a region, for the territory panel, from P4's
## FactionTable (fight/faction_table.gd over data/combat/factions.json) under
## the enemy-factions variant the player chose. A region no faction holds
## (the generic roster, or a map outside every act) gives {} and the panel
## shows nothing.

var table: FactionTable
## Returns the enemy-factions rule (a FightVariants option) to read the
## table under; read on each lookup, so a switchboard change shows at once.
var rule_source: Callable = func() -> String:
	return FightVariants.load_active().option(FightVariants.ENEMY_FACTIONS)


func _init(p_table: FactionTable = null) -> void:
	table = p_table


## The lookup over the shipped table.
static func load_default() -> FactionLookup:
	return FactionLookup.new(FactionTable.load_default())


## The faction holding `region_id`: {"id", "name", "color": Color,
## "icon": Texture2D or null}, or {} when none does.
func faction_for(region_id: String) -> Dictionary:
	if table == null:
		return {}
	var rule: String = rule_source.call() if rule_source.is_valid() else FightVariants.FACTIONS_BY_ACT
	var id := table.faction_for_region(region_id, rule)
	if id == FactionTable.GENERIC:
		return {}
	var icon_path := table.faction_icon(id)
	var icon: Texture2D = load(icon_path) as Texture2D if not icon_path.is_empty() and ResourceLoader.exists(icon_path) else null
	return {"id": id, "name": table.faction_name(id), "color": table.faction_color(id), "icon": icon}
