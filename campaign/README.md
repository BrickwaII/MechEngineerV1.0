# campaign/

Layer 3. Map, time, pressure, run state. May import contracts only until the integration step.

- `region_map.gd`, `map_region.gd`: load and check a region file from data/regions/.
- `map_tuning.gd`: every overworld number, from data/tuning/overworld.json.
- `campaign.gd`: the rules. Ownership, adjacency, time, pressure, grid, and
  fights through SquadProvider and FightService. Runs headless.
- `run_state.gd`: what a save keeps; saves and loads exactly.
