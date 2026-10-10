class_name DevToolSettings
extends RefCounted
## Settings for the dev tools, read from data/scenarios/_dev_tools.json.

const DEFAULT_PATH := "res://data/scenarios/_dev_tools.json"

var default_runs: int
var default_base_seed: int
## Where each simulated fight appends its stats record (JSON lines).
var stats_log_path: String
## Folders the builders save bots, enemies and scenarios into.
var bot_dir: String
var enemy_dir: String
var scenario_dir: String
## How many upcoming actions the debug overlay lists.
var overlay_timeline_count: int
var overlay_refresh_seconds: float
var demo_seconds_per_action: float
## Upper bounds for the builder's spin boxes.
var builder_max_stat: int
var builder_max_skill_level: int
## Variant comparison defaults: enemy level, each side's policy, and fights
## per run for decisions that act between fights.
var compare_defense_level: int
var compare_player_policy: String
var compare_enemy_policy: String
var compare_chain_fights: int
## Campaign comparison (CampaignComparison, CampaignAutoplay): runs per
## option, the pressure at which the auto-player reinforces, and the most
## actions it takes in one act before giving up.
var campaign_compare_runs: int
var autoplay_reinforce_at: float
var autoplay_max_actions_per_act: int


static func load_default() -> DevToolSettings:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> DevToolSettings:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("DevToolSettings: cannot read %s" % path)
		return null
	var d: Dictionary = parsed
	var s := DevToolSettings.new()
	s.default_runs = int(d.default_runs)
	s.default_base_seed = int(d.default_base_seed)
	s.stats_log_path = str(d.stats_log_path)
	s.bot_dir = str(d.bot_dir)
	s.enemy_dir = str(d.enemy_dir)
	s.scenario_dir = str(d.scenario_dir)
	s.overlay_timeline_count = int(d.overlay_timeline_count)
	s.overlay_refresh_seconds = float(d.overlay_refresh_seconds)
	s.demo_seconds_per_action = float(d.demo_seconds_per_action)
	s.builder_max_stat = int(d.builder_max_stat)
	s.builder_max_skill_level = int(d.builder_max_skill_level)
	s.compare_defense_level = int(d.compare_defense_level)
	s.compare_player_policy = str(d.compare_player_policy)
	s.compare_enemy_policy = str(d.compare_enemy_policy)
	s.compare_chain_fights = int(d.compare_chain_fights)
	s.campaign_compare_runs = int(d.campaign_compare_runs)
	s.autoplay_reinforce_at = float(d.autoplay_reinforce_at)
	s.autoplay_max_actions_per_act = int(d.autoplay_max_actions_per_act)
	return s
