class_name HarnessSettings
extends RefCounted
## Settings for the simulation harness (PolicyComparison), read from
## data/scenarios/_harness.json: the policies compared, runs, the default
## scenario, the CSV folder and the exit checks' thresholds.

const DEFAULT_PATH := "res://data/scenarios/_harness.json"

## FightScenario policy names, in table order.
var policies: Array[String] = []
var runs := 100
var base_seed := 1
## The scenario played when none is named.
var scenario := ""
var csv_dir := ""
## The policy that plays well and the one that plays greedily, for the checks.
var clean_policy := ""
var careless_policy := ""
## No action may take more than this share of the clean policy's decisions.
var max_action_share_percent := 50
## How much more HP (percent) the careless policy must lose to count as clear.
var clear_gap_percent := 10


static func load_default() -> HarnessSettings:
	return load_file(DEFAULT_PATH)


## The settings in `path`, or null (with the problems pushed as errors).
static func load_file(path: String) -> HarnessSettings:
	var parsed: Variant = JsonFile.read_object(path)
	if parsed == null:
		push_error("HarnessSettings: cannot read %s" % path)
		return null
	var s := from_dict(parsed)
	var problems := s.validate()
	if not problems.is_empty():
		push_error("HarnessSettings: %s: %s" % [path, "; ".join(problems)])
		return null
	return s


static func from_dict(d: Dictionary) -> HarnessSettings:
	var s := HarnessSettings.new()
	for p: Variant in d.get("policies", []):
		s.policies.append(str(p))
	s.runs = int(d.get("runs", s.runs))
	s.base_seed = int(d.get("base_seed", s.base_seed))
	s.scenario = str(d.get("scenario", ""))
	s.csv_dir = str(d.get("csv_dir", ""))
	s.clean_policy = str(d.get("clean_policy", ""))
	s.careless_policy = str(d.get("careless_policy", ""))
	s.max_action_share_percent = int(d.get("max_action_share_percent", s.max_action_share_percent))
	s.clear_gap_percent = int(d.get("clear_gap_percent", s.clear_gap_percent))
	return s


func validate() -> Array[String]:
	var problems: Array[String] = []
	if policies.is_empty():
		problems.append("no policies")
	for p in policies + [clean_policy, careless_policy]:
		if not p in FightScenario.POLICIES:
			problems.append("unknown policy '%s'" % p)
	if runs < 1:
		problems.append("runs must be at least 1")
	if max_action_share_percent < 1 or max_action_share_percent > 100:
		problems.append("max_action_share_percent must be 1 to 100")
	if clear_gap_percent < 0:
		problems.append("clear_gap_percent must not be negative")
	return problems
