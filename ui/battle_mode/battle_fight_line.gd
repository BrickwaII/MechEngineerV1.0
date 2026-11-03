class_name BattleFightLine
extends HBoxContainer
## One Battle Mode fight as a row of icons and numbers (ui/README.md rule 1):
## outcome, turns, HP lost, energy spent and wasted, the most-used action's
## share, combos and Staggers. Each icon's tooltip says what it counts and
## how; the full line is the row's own tooltip. Used under the post-fight
## readout and on the end-of-run summary.

var record: BattleFightRecord
## Action id -> name, for the top action.
var names: Callable
## An action above this share of the turns is flagged (data/battle_mode/).
var dominant_share_percent := 50
## Compact: the outcome as an icon only (its word is in the tooltip).
var compact := false


static func make(p_record: BattleFightRecord, p_names: Callable, p_dominant := 50, p_compact := false) -> BattleFightLine:
	var row := BattleFightLine.new()
	row.name = "FightLine%d" % p_record.fight_number
	row.record = p_record
	row.names = p_names
	row.dominant_share_percent = p_dominant
	row.compact = p_compact
	row.add_theme_constant_override("separation", UiStyle.space("m"))
	row._build()
	return row


func _build() -> void:
	var r := record
	tooltip_text = r.line(names)
	add_child(IconStat.make("fights_won" if r.victory else "fights_lost", null if compact else ("Won" if r.victory else "Lost"),
		"Fight %d (%s) %s" % [r.fight_number, r.kind, "won" if r.victory else "lost"]))
	add_child(IconStat.make("time", r.turns,
		"Turns: the squad's decisions this fight (skills and waits). %d decisions in all, both sides." % r.actions))
	var hp := IconStat.make("hp", -r.hp_lost(), "HP lost by the squad this fight.")
	hp.set_math([UiFormula.parse("{START} − {END}", {"START": r.hp_start, "END": r.hp_end}, r.hp_lost())])
	add_child(hp)
	add_child(IconStat.make("energy", TextFormat.short_number(r.energy_spent()), "Energy the squad spent."))
	add_child(IconStat.make("battery", TextFormat.short_number(r.energy_wasted()),
		"Energy wasted: recharge lost because a battery was already full."))
	var top := r.top_action()
	if not top.is_empty():
		var share := IconStat.make("odds", "%s %d%%" % [str(names.call(top)) if names.is_valid() else top, r.top_share_percent()],
			"The most-used action and its share of the squad's turns. Above %d%% one button is doing too much." % dominant_share_percent)
		if r.is_dominated(dominant_share_percent):
			share.value_label.add_theme_color_override("font_color", UiStyle.role("caution"))
		share.name = "TopAction"
		add_child(share)
	add_child(IconStat.make("multiplier", r.combos, "Combos: hits that cashed in a setup (Exposed, a payoff bonus)."))
	add_child(IconStat.make("status_intent_changed", r.staggers, "Staggers: enemy plating broken by the squad."))
