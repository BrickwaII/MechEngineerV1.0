class_name FightVariants
extends VariantSet
## The fight layer's switches from the variant switchboard
## (data/variants/variants.json): one chosen option per fight decision, and
## that option's params. Only decisions with "layer": "fight" are read.
##
##   var v := FightVariants.load_active()     # defaults + the player's choices
##   if v.option(FightVariants.WAIT_FORM) == FightVariants.WAIT_EXTRA_ENERGY: ...
##
## defaults() ignores the player's choices; tests and CombatTuning use it, so
## a choice saved in user:// never changes a test. The game loads the active
## set when each fight starts (see ui/run/).

const DEFAULT_PATH := "res://data/variants/variants.json"
## The player's choices, written by the switchboard screen (ui/dev/).
const USER_PATH := "user://variants.json"
const LAYER := "fight"

const WAIT_FORM := "d-wait"
const WAIT_BANKED := "banked"
const WAIT_EXTRA_ENERGY := "extra_energy"
const WAIT_BONUS_DAMAGE := "bonus_damage"

const WAIT_LENGTH := "d-wait-length"
const WAIT_LENGTH_SNAP := "snap"
const WAIT_LENGTH_EXACT := "exact"

const ELASTICITY := "d-elasticity"
const ELASTICITY_NONE := "none"
const ELASTICITY_BIG_HITS := "reduce_big_hits"
const ELASTICITY_KNOCKBACK := "resist_knockback"
const ELASTICITY_ENERGY := "energy_when_hit"

const PERSONALITY_MAP := "d-personality-map"
const PERSONALITY_CURRENT := "current"
const PERSONALITY_BY_TARGET := "by_target"
const PERSONALITY_OFF := "off"

## How bot skills grow. TODO(decision: skill-ranks).
const SKILL_PROGRESSION := "skill-progression"
const PROGRESSION_RANKS := "ranks"
const PROGRESSION_FLAT := "flat_levels"

## What one tagged decision counts for in personality drift.
const TAG_WEIGHT := "tag-weight"
const TAG_WEIGHT_PER_ACTION := "per_action"
const TAG_WEIGHT_PER_ENERGY := "per_energy"
## A decision counts reference_speed / the bot's speed: weight per unit of
## turn time, so a bot that acts less often counts more per decision.
const TAG_WEIGHT_PER_TURN_TIME := "per_turn_time"
## Each bot's decisions share a fixed budget of pushes per fight
## (pushes_per_fight), however many decisions it made.
const TAG_WEIGHT_PER_FIGHT := "per_fight"

## How far apart the fastest and slowest units act, and what slow units get
## for it. See SpeedRules. TODO(decision: speed-range).
const SPEED_RANGE := "speed-range"
const SPEED_WIDE := "wide"
const SPEED_COMPRESSED := "compressed"

## What the basic attack (Strike) costs, and the energy recharge that goes
## with it. See EnergyRules. TODO(decision: strike-cost).
const STRIKE_COST := "strike-cost"
const STRIKE_FREE := "free"
const STRIKE_COSTS := "costs"

## Enemy tiers per act and act scaling. See DifficultyRules.
## TODO(decision: difficulty-targets).
const DIFFICULTY_CURVE := "difficulty-curve"
const DIFFICULTY_FLAT := "flat"
const DIFFICULTY_TUNED := "tuned"

const HP_CARRYOVER := "hp-carryover"
const HP_FULL_HEAL := "full_heal"
const HP_CARRY := "carry"
const HP_PARTIAL_HEAL := "partial_heal"

const ENEMY_FACTIONS := "enemy-factions"
const FACTIONS_BY_ACT := "by_act"
const FACTIONS_MIXED := "mixed"
const FACTIONS_GENERIC := "generic"

## How the map judges odds (read by the overworld through OddsEstimator).
const ODDS_MODEL := "odds-model"
const ODDS_SIMULATED := "simulated"
const ODDS_FORMULA := "formula"

## Every fight decision this class knows, with the options code implements.
const KNOWN := {
	WAIT_FORM: [WAIT_BANKED, WAIT_EXTRA_ENERGY, WAIT_BONUS_DAMAGE],
	WAIT_LENGTH: [WAIT_LENGTH_SNAP, WAIT_LENGTH_EXACT],
	ELASTICITY: [ELASTICITY_NONE, ELASTICITY_BIG_HITS, ELASTICITY_KNOCKBACK, ELASTICITY_ENERGY],
	PERSONALITY_MAP: [PERSONALITY_CURRENT, PERSONALITY_BY_TARGET, PERSONALITY_OFF],
	SKILL_PROGRESSION: [PROGRESSION_RANKS, PROGRESSION_FLAT],
	TAG_WEIGHT: [TAG_WEIGHT_PER_ACTION, TAG_WEIGHT_PER_ENERGY, TAG_WEIGHT_PER_TURN_TIME, TAG_WEIGHT_PER_FIGHT],
	SPEED_RANGE: [SPEED_WIDE, SPEED_COMPRESSED],
	STRIKE_COST: [STRIKE_FREE, STRIKE_COSTS],
	DIFFICULTY_CURVE: [DIFFICULTY_FLAT, DIFFICULTY_TUNED],
	HP_CARRYOVER: [HP_FULL_HEAL, HP_CARRY, HP_PARTIAL_HEAL],
	ENEMY_FACTIONS: [FACTIONS_BY_ACT, FACTIONS_MIXED, FACTIONS_GENERIC],
	ODDS_MODEL: [ODDS_SIMULATED, ODDS_FORMULA],
}

static var _cached_defaults: Dictionary = {}


## The data file's defaults, with no player choices. The file is read once.
static func defaults() -> FightVariants:
	if _cached_defaults.is_empty():
		_cached_defaults = JsonFile.read_dict(DEFAULT_PATH)
	return from_dict(_cached_defaults)


## The defaults with the player's choices from `user_path` on top. A missing
## or broken user file is ignored, as is a choice of an unknown option.
static func load_active(user_path := USER_PATH) -> FightVariants:
	var v := defaults()
	var user := JsonFile.read_dict(user_path) if FileAccess.file_exists(user_path) else {}
	v.choose_all(user.get("choices", {}))
	return v


static func from_dict(data: Dictionary) -> FightVariants:
	var v := FightVariants.new()
	v.read_decisions(data, LAYER, KNOWN)
	return v


func duplicate_variants() -> FightVariants:
	return copy_into(FightVariants.new())
