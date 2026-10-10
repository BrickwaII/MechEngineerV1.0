# campaign/

Layer 3. Map, time, pressure, run state. May import contracts only until the integration step.

- `region_map.gd`, `map_region.gd`: load and check a region file from data/regions/,
  with its optional starting locations and water.
- `start_option.gd`: one starting location: the regions it holds and its traits.
- `map_tuning.gd`: every overworld number, from data/tuning/overworld.json.
- `act_plan.gd`: the acts of a run and what carries across the zoom between
  them, from data/tuning/acts.json.
- `campaign.gd`: the rules. Ownership, adjacency, time, pressure, grid, and
  fights through SquadProvider and FightService. Runs headless.
- `run_state.gd`: what a save keeps, including the act and the start's
  traits; saves and loads exactly.
