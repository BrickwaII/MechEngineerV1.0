# bot_data/

Layer 1. Pure bot state: stats, personality, skills, augment slots. No behavior.

State (Resources, saved to disk):
- `bot.gd` (Bot): id, name, current HP, six stats (contracts/UnitStats), personality, skills, augment slots, and the generation band (`skill_level_band`, the levels its skills may reach; stored only until S15 of the combat rework).
- `personality.gd` (Personality): three spectrums, each with two ends that never go below 0 and have no cap; the lean is the larger end. The generation decides how many spectrums the intent planner weighs. Format-1 signed values split onto the ends as a file loads.
- `skill.gd` (Skill): name, effect id, flat energy cost, per-bot level (a named rank with skill-progression = ranks).
- `augment_slot.gd` (AugmentSlot): an empty slot. Structure only.
- `bot_squad.gd` (BotSquad): the drafted bots and which are fielded.

Helpers (RefCounted):
- `bot_tuning.gd` (BotTuning): reads and validates data/bot_data/, including the active-skill slot count (`active_skill_slots`, `slotted_skill_count()`; the basic attack takes no slot) and the starting generation band.
- `bot_factory.gd` (BotFactory): a seeded draft; the same seed gives the same bots.
- `bot_squad_storage.gd` (BotSquadStorage): saves and loads a BotSquad.
- `bot_squad_provider.gd` (BotSquadProvider): contracts/SquadProvider over a real BotSquad.

Overworld swap-in:

    var tuning := BotTuning.load_default()
    var provider := BotSquadProvider.new(BotFactory.new(tuning).build_squad(run_seed))
