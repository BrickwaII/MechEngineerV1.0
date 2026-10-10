# fight/

Layer 2. Combat, energy, intent, preview, post-fight. May import bot_data and contracts.

Combat core (M2), pure logic with no scenes:
- `Fight`: one fight in ATB wait mode. `advance()` runs time until a unit is
  ready, `submit()` resolves its action. `upcoming(n)` previews the order.
- `Timeline`: gauge-based turn order. `Combatant`: per-unit hp, energy, gauge.
- `DamageRules`: deterministic damage. `CombatTuning`, `EnemyTable`: read
  data/combat/.
- `HeadlessFightRunner`: plays a fight from a seed and policies, with a text log.
- `AutoFightService`: a contracts FightService built on the runner.
