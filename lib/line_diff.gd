class_name LineDiff
extends RefCounted
## A line diff of two texts, for showing a change before it is written:
##
##   print(LineDiff.unified(old_text, new_text, "data/combat/actions.json"))
##
## Lines are matched by their longest common subsequence, so a changed line
## reads as "-" then "+". Meant for data files of a few hundred lines.

const SAME := " "
const REMOVED := "-"
const ADDED := "+"


## One entry per line of the two texts, in order: [mark, line], where mark
## is SAME, REMOVED (only in `a`) or ADDED (only in `b`).
static func ops(a: String, b: String) -> Array:
	var x := a.split("\n")
	var y := b.split("\n")
	var n := x.size()
	var m := y.size()
	# lcs[i * w + j]: the common subsequence length of x[i..] and y[j..].
	var w := m + 1
	var lcs := PackedInt32Array()
	lcs.resize((n + 1) * w)
	lcs.fill(0)
	for i in range(n - 1, -1, -1):
		for j in range(m - 1, -1, -1):
			if x[i] == y[j]:
				lcs[i * w + j] = lcs[(i + 1) * w + j + 1] + 1
			else:
				lcs[i * w + j] = maxi(lcs[(i + 1) * w + j], lcs[i * w + j + 1])
	var out := []
	var p := 0
	var q := 0
	while p < n and q < m:
		if x[p] == y[q]:
			out.append([SAME, x[p]])
			p += 1
			q += 1
		elif lcs[(p + 1) * w + q] >= lcs[p * w + q + 1]:
			out.append([REMOVED, x[p]])
			p += 1
		else:
			out.append([ADDED, y[q]])
			q += 1
	while p < n:
		out.append([REMOVED, x[p]])
		p += 1
	while q < m:
		out.append([ADDED, y[q]])
		q += 1
	return out


## True when the texts differ.
static func differs(a: String, b: String) -> bool:
	return a != b


## The changed lines with `context` unchanged lines around each change,
## headed by the file name; "" when the texts are the same. Gaps between
## shown parts are marked "...".
static func unified(a: String, b: String, name := "", context := 1) -> String:
	if a == b:
		return ""
	var all := ops(a, b)
	var keep := PackedByteArray()
	keep.resize(all.size())
	keep.fill(0)
	for k in all.size():
		if all[k][0] != SAME:
			for c in range(maxi(0, k - context), mini(all.size(), k + context + 1)):
				keep[c] = 1
	var lines := PackedStringArray()
	if not name.is_empty():
		lines.append("--- " + name)
		lines.append("+++ " + name)
	var gap := false
	var shown_any := false
	for k in all.size():
		if keep[k] == 0:
			gap = true
			continue
		# "..." only between two shown parts, never before the first.
		if gap and shown_any:
			lines.append("...")
		gap = false
		shown_any = true
		lines.append("%s %s" % [all[k][0], all[k][1]])
	return "\n".join(lines)


## How many lines were removed and added: {"removed": int, "added": int}.
static func counts(a: String, b: String) -> Dictionary:
	var removed := 0
	var added := 0
	for op: Array in ops(a, b):
		if op[0] == REMOVED:
			removed += 1
		elif op[0] == ADDED:
			added += 1
	return {"removed": removed, "added": added}
