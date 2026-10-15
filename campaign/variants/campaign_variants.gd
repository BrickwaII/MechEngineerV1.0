class_name CampaignVariants
extends VariantSet
## The campaign layer's switches from the variant switchboard
## (data/variants/variants.json): one chosen option per campaign decision, and
## that option's params. Only decisions with "layer": "campaign" and options of
## their own are read (act-maps is applied by the run flow, not here).
##
##   var v := CampaignVariants.load_active()   # defaults + the player's choices
##   if v.is_chosen(CampaignVariants.AUTO_EXPANSION, CampaignVariants.EXPANSION_SIMPLE): ...
##
## When each takes effect:
## - next_run (energy-grid, squad-size, act-pacing, auto-expansion,
##   loss-limit, resource-uses, resource-cap, escalation): read once
##   when a run starts and kept in RunState.variants, so a saved run plays on
##   with the choices it began with. for_run() rebuilds them from a state.
## - next_fight (grid-cost-owner): read when each fight starts.
##
## user_path names the player's choices file. It is "" by default, which reads
## the defaults only, so a choice saved in user:// never changes a test; the
## run flow (ui/run/) points it at the switchboard's file.

const DEFAULT_PATH := "res://data/variants/variants.json"
const LAYER := "campaign"

const ENERGY_GRID := "energy-grid"
const ENERGY_SEPARATE := "separate"
const ENERGY_SHARED_POOL := "shared_pool"

const GRID_COST_OWNER := "grid-cost-owner"
const GRID_MAP_SURCHARGE := "map_surcharge"
const GRID_FIGHT_SERVICE := "fight_service"
const GRID_NO_SURCHARGE := "no_surcharge"

const SQUAD_SIZE := "squad-size"
const SQUAD_DRAFT5_FIELD3 := "draft5_field3"
const SQUAD_DRAFT4_FIELD3 := "draft4_field3"
const SQUAD_DRAFT6_FIELD4 := "draft6_field4"

const ACT_PACING := "act-pacing"
const PACING_CURRENT := "current"
const PACING_EVEN := "even"
const PACING_FASTER_LATER := "faster_later"

const ESCALATION := "escalation"
const ESCALATION_ON := "on"
const ESCALATION_OFF := "off"
const ESCALATION_QUARTERS := "quarters"

const AUTO_EXPANSION := "auto-expansion"
const EXPANSION_OFF := "off"
const EXPANSION_SIMPLE := "simple"

const LOSS_LIMIT := "loss-limit"
const LOSSES_THREE_PER_ACT := "three_per_act"
const LOSSES_ONE := "one_loss"
const LOSSES_UNLIMITED := "unlimited"
## The limit grows with the act's length. TODO(decision: loss-limit).
const LOSSES_SCALED := "scaled"

## Which lost battles count toward the loss limit. TODO(decision: loss-limit).
const LOSS_COUNT := "loss-count"
const LOSS_COUNT_ALL := "all"
const LOSS_COUNT_ATTACKS_ONLY := "attacks_only"

const RESOURCE_USES := "resource-uses"
const USES_SPLIT := "split"
const USES_SWAPPED := "swapped"

const RESOURCE_CAP := "resource-cap"
const CAP_CAPPED := "capped"
const CAP_UNCAPPED := "uncapped"

## Every campaign decision this class knows, with the options code implements.
const KNOWN := {
	ENERGY_GRID: [ENERGY_SEPARATE, ENERGY_SHARED_POOL],
	GRID_COST_OWNER: [GRID_MAP_SURCHARGE, GRID_FIGHT_SERVICE, GRID_NO_SURCHARGE],
	SQUAD_SIZE: [SQUAD_DRAFT5_FIELD3, SQUAD_DRAFT4_FIELD3, SQUAD_DRAFT6_FIELD4],
	ACT_PACING: [PACING_CURRENT, PACING_EVEN, PACING_FASTER_LATER],
	AUTO_EXPANSION: [EXPANSION_OFF, EXPANSION_SIMPLE],
	LOSS_LIMIT: [LOSSES_THREE_PER_ACT, LOSSES_ONE, LOSSES_UNLIMITED, LOSSES_SCALED],
	LOSS_COUNT: [LOSS_COUNT_ALL, LOSS_COUNT_ATTACKS_ONLY],
	RESOURCE_USES: [USES_SPLIT, USES_SWAPPED],
	RESOURCE_CAP: [CAP_CAPPED, CAP_UNCAPPED],
	ESCALATION: [ESCALATION_ON, ESCALATION_OFF, ESCALATION_QUARTERS],
}
## The decisions a run keeps from its start (applies: next_run).
const RUN_DECISIONS: Array[String] = [ENERGY_GRID, SQUAD_SIZE, ACT_PACING, AUTO_EXPANSION, LOSS_LIMIT, LOSS_COUNT, RESOURCE_USES, RESOURCE_CAP, ESCALATION]

## The player's choices file; "" reads the defaults only. See the class notes.
static var user_path := ""

## The option a run plays for a run decision added after it began: a save or
## journal from before escalation keeps the difficulty it was played with.
const BEFORE_DECISION := {ESCALATION: ESCALATION_OFF}

static var _cached_defaults: Dictionary = {}


## The data file's defaults, with no player choices. The file is read once.
static func defaults() -> CampaignVariants:
	if _cached_defaults.is_empty():
		_cached_defaults = JsonFile.read_dict(DEFAULT_PATH)
	return from_dict(_cached_defaults)


## The defaults with the player's choices from `path` on top (user_path when
## left empty). A missing or broken file is ignored, as is an unknown option.
static func load_active(path := "") -> CampaignVariants:
	var v := defaults()
	var file := path if not path.is_empty() else user_path
	if file.is_empty() or not FileAccess.file_exists(file):
		return v
	v.choose_all(JsonFile.read_dict(file).get("choices", {}))
	return v


## The defaults with a run's kept choices (RunState.variants) on top. A save
## from before variants keeps none, so it plays every default, except that a
## run from before a decision in BEFORE_DECISION plays the option given there.
static func for_run(run_choices: Dictionary) -> CampaignVariants:
	var v := defaults()
	for decision: String in BEFORE_DECISION:
		if not run_choices.has(decision):
			v.choose(decision, BEFORE_DECISION[decision])
	for decision: Variant in run_choices:
		if str(decision) in RUN_DECISIONS:
			v.choose(str(decision), str(run_choices[decision]))
	return v


static func from_dict(data: Dictionary) -> CampaignVariants:
	var v := CampaignVariants.new()
	v.read_decisions(data, LAYER, KNOWN, true)
	return v


## The choices a run keeps from its start, every run decision included, for
## RunState.variants.
func run_choices() -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for id in RUN_DECISIONS:
		out[id] = option(id)
	return out


## {draft_size, squad_size} for the chosen squad-size option, or {} when it
## keeps data/bot_data/tuning.json's sizes (the default gives no params).
func squad_sizes() -> Dictionary:
	var p := params(SQUAD_SIZE)
	if not p.has("draft_size") or not p.has("squad_size"):
		return {}
	return {"draft_size": int(p["draft_size"]), "squad_size": int(p["squad_size"])}


func duplicate_variants() -> CampaignVariants:
	return copy_into(CampaignVariants.new())
