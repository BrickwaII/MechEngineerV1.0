class_name MapChanges
extends RefCounted
## What changed on the map between two looks at a run, with no scene: regions
## taken and lost, and how much energy, material and grid moved. The overworld
## takes a snapshot after every refresh, and shows the difference as a capture
## animation, number popups and bar slides once the map is in view.

const KEYS := ["energy", "material", "grid"]

var captured: PackedStringArray = []
var lost: PackedStringArray = []
## "energy", "material", "grid" -> change; only keys that moved.
var deltas := {}


## What `state` looks like for the next diff.
static func snapshot(state: RunState) -> Dictionary:
	return {"owned": state.owned.duplicate(), "energy": state.energy, "material": state.material, "grid": state.grid}


## The changes from `before` to `after`, two snapshots.
static func between(before: Dictionary, after: Dictionary) -> MapChanges:
	var out := MapChanges.new()
	var was: PackedStringArray = before.get("owned", PackedStringArray())
	var now: PackedStringArray = after.get("owned", PackedStringArray())
	for id in now:
		if not id in was:
			out.captured.append(id)
	for id in was:
		if not id in now:
			out.lost.append(id)
	for key: String in KEYS:
		var delta := float(after.get(key, 0.0)) - float(before.get(key, 0.0))
		if absf(delta) >= 0.5:
			out.deltas[key] = delta
	return out


func is_empty() -> bool:
	return captured.is_empty() and lost.is_empty() and deltas.is_empty()


## Folds `later` into this one, for changes that pile up while the map is
## out of sight: a region taken then lost again cancels out.
func merge(later: MapChanges) -> void:
	for id in later.captured:
		if id in lost:
			lost.remove_at(lost.find(id))
		elif not id in captured:
			captured.append(id)
	for id in later.lost:
		if id in captured:
			captured.remove_at(captured.find(id))
		elif not id in lost:
			lost.append(id)
	for key: String in later.deltas:
		deltas[key] = deltas.get(key, 0.0) + later.deltas[key]
		if absf(deltas[key]) < 0.5:
			deltas.erase(key)
