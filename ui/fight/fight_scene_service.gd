class_name FightSceneService
extends FightService
## A contracts FightService that plays each fight as a BattleScreen under
## `host`, with the player choosing every bot action. When the fight ends the
## screen is removed and finished is emitted with Fight.result(). Drop-in for
## StubFightService and AutoFightService.
##
##   var service := FightSceneService.new(self)
##   service.finished.connect(_on_fight_finished)
##   service.start_fight(request)
##
## The seed comes from the request, as in AutoFightService, unless
## `fixed_seed` is set. finished always comes a frame or more after
## start_fight(), as the contract requires.

const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")
const NO_FIXED_SEED := -1

## Emitted when a screen is shown, so callers can hide what is behind it.
signal screen_opened(screen: BattleScreen)

var host: Node
var fixed_seed := NO_FIXED_SEED
## Screen tuning; null means data/ui/fight_screen.json.
var tuning: FightScreenTuning
var combat_tuning: CombatTuning
var enemy_table: EnemyTable
## The screen of the fight in progress, or null.
var screen: BattleScreen
## The last fight played, kept for logs and debugging.
var last_fight: Fight


func _init(p_host: Node, p_tuning: FightScreenTuning = null) -> void:
	host = p_host
	tuning = p_tuning


func start_fight(request: FightRequest) -> void:
	if screen != null:
		push_error("FightSceneService: a fight is already running")
		return
	screen = BATTLE_SCENE.instantiate()
	screen.setup(request, seed_for(request), tuning, combat_tuning, enemy_table)
	last_fight = screen.fight
	screen.fight_finished.connect(_on_fight_finished, CONNECT_ONE_SHOT)
	host.add_child(screen)
	screen_opened.emit(screen)


func seed_for(request: FightRequest) -> int:
	if fixed_seed != NO_FIXED_SEED:
		return fixed_seed
	# The same formula as AutoFightService, so both play the same enemies.
	return hash("%s:%d:%d" % [request.territory_id, request.kind, request.defense_level])


func _on_fight_finished(result: FightResult) -> void:
	var done := screen
	screen = null
	# The last action may resolve inside start_fight()'s frame (an invalid
	# request ends at once), so report on the next frame, never sooner.
	await Engine.get_main_loop().process_frame
	if is_instance_valid(done):
		done.queue_free()
	finished.emit(result)
