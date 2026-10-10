class_name ActPacing
extends RefCounted
## The act-pacing decision: each act's countdown and action costs.
## TODO(decision: act-pacing).
##
## current (the default): each act plays its own tuning file
##   (data/tuning/act*.json): today a 100-day countdown each, the same action
##   costs, and pressure scaled by region count.
## even, faster_later: presets. The option's params hold "acts", one tuning
##   override per act in order, laid over that act's tuning file the way a
##   tuning file lays over its base (MapTuning.with_overrides()). An act
##   with no entry, or an empty one, plays its file unchanged.
##   - even: every act a 100-day countdown at the shipped costs, whatever the
##     act files say.
##   - faster_later: a longer act 1 and shorter acts 2 and 3, the same points
##     in total, so a whole run takes about as long while later acts move
##     faster.


## `tuning` for act index `act` under the run's pacing.
static func paced(tuning: MapTuning, act: int, v: CampaignVariants) -> MapTuning:
	var acts: Variant = v.params(CampaignVariants.ACT_PACING).get("acts", [])
	if not acts is Array or act < 0 or act >= (acts as Array).size():
		return tuning
	var over: Variant = acts[act]
	if not over is Dictionary or (over as Dictionary).is_empty():
		return tuning
	return tuning.with_overrides(over)
