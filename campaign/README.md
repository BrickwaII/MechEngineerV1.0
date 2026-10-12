# campaign/

Layer 3. Map, time, pressure, run state. May import contracts only until the integration step.

- `region_map.gd`, `map_region.gd`: load and check a region file from data/regions/,
  with its optional starting locations, water, land, water crossings and zoom
  inset; flat (0 to 1) or globe (longitude, latitude) points; region_at() finds
  the region under a map-space point. Format: data/regions/README.md.
- `start_option.gd`: one starting location: the regions it holds and its traits.
- `map_tuning.gd`: every overworld number, from data/tuning/overworld.json;
  an act's file (data/tuning/act*.json) names it as its "base" and overrides
  its pacing.
- `act_plan.gd`: the acts of a run, each act's map variants and the chosen one,
  and what carries across the zoom between them, from data/tuning/acts.json.
- `campaign.gd`: the rules. Ownership, adjacency, time, pressure, grid, and
  fights through SquadProvider and FightService. Runs headless.
- `escalation.gd`: alert tiers (three per act, raised by holding 1/3 and 2/3
  of the map, never dropping), the defense level each hostile region fights
  at by tier, fortifying of regions left alone on alert, and news cards.
  Numbers and headlines in data/tuning/escalation.json; state in
  RunState.escalation; the `escalation` variant turns it off or lowers the
  thresholds.
- `stakes.gd` (R2-A): what losing costs and what Energy and Material buy.
  Numbers from the tuning's "stakes" section (data/tuning/overworld.json) and
  the switchboard's loss-limit and resource-uses decisions. Campaign uses it
  for the loss limit (state.losses, state.ended), retreat, breach, repair,
  reinforce costs and fast_forward().
- `run_state.gd`: what a save keeps, including the act and the start's
  traits; saves and loads exactly.
- `variants/`: the campaign side of the variant switchboard
  (data/variants/variants.json). `campaign_variants.gd` reads the campaign
  decisions; each decision's rules are one small module:
  - `energy_grid_rules.gd` (energy-grid): Energy and grid separate, or one
    shared pool; the spend and regen rules are in the file's notes.
  - `grid_cost_owner.gd` (grid-cost-owner): who adds the defeat surcharge.
  - `act_pacing.gd` (act-pacing): per-act tuning presets laid over the act
    files.
  - `auto_expansion.gd` (auto-expansion): held ground claiming weak
    neighbors on a daily progress meter, faster near the player's focus.
  squad-size is applied to the draft's bot tuning by the run flow (ui/run/).
  Next-run choices are kept in RunState.variants when a run starts, so a save
  plays on with them; grid-cost-owner is read when each fight starts.
  `screenshots/` holds the switchboard and a map with auto-expansion on.
