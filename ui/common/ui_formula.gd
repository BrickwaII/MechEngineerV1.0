class_name UiFormula
extends RefCounted
## A formula line built from the real values, so a tooltip can show how a
## number came about:
##
##   UiFormula.new().term("ATK", 12).op("−").term("DEF", 8).op("×") \
##       .open().num(1).op("−").term("Pierce", "20%").close().equals(6).text()
##   -> "ATK 12 − DEF 8 × (1 − Pierce 20%) = 6"
##
## or from a template whose {Name} tokens name values:
##
##   UiFormula.parse("{ATK} − {DEF} × (1 − {Pierce})",
##       {"ATK": 12, "DEF": 8, "Pierce": "20%"}, 6)
##
## Give it to a tooltip with UiTooltip.set_math(control, [formula.text()]) or
## the `math` argument of the kit widgets. bbcode() colors it: values bright,
## operators quiet, the result in the hint color.

## Each part: {"kind": "term" | "num" | "op", "label": String, "value": Variant}.
var parts: Array[Dictionary] = []
var result: Variant = null
var result_label := ""


static func parse(template: String, values: Dictionary, p_result: Variant = null, p_result_label := "") -> UiFormula:
	var f := UiFormula.new()
	var i := 0
	while i < template.length():
		var start := template.find("{", i)
		if start < 0:
			f._ops(template.substr(i))
			break
		f._ops(template.substr(i, start - i))
		var end := template.find("}", start)
		if end < 0:
			f._ops(template.substr(start))
			break
		var key := template.substr(start + 1, end - start - 1)
		f.term(key, values.get(key, "?"))
		i = end + 1
	if p_result != null:
		f.equals(p_result, p_result_label)
	return f


## A value as a formula shows it: whole floats without decimals, others to
## two places at most; Strings as they are.
static func fmt(v: Variant) -> String:
	if v is float:
		if is_equal_approx(v, roundf(v)):
			return str(int(roundf(v)))
		return String.num(v, 2)
	return str(v)


## A share as a percent: 0.2 -> "20%".
static func percent(share: float) -> String:
	return "%s%%" % fmt(share * 100.0)


## A named value: "ATK 12".
func term(label: String, value: Variant) -> UiFormula:
	parts.append({"kind": "term", "label": label, "value": value})
	return self


## A bare number: "1".
func num(value: Variant) -> UiFormula:
	parts.append({"kind": "num", "label": "", "value": value})
	return self


## An operator or other symbol: "−", "×", "/", "+".
func op(symbol: String) -> UiFormula:
	parts.append({"kind": "op", "label": symbol, "value": null})
	return self


func open() -> UiFormula:
	return op("(")


func close() -> UiFormula:
	return op(")")


func equals(value: Variant, label := "") -> UiFormula:
	result = value
	result_label = label
	return self


## The line as plain text.
func text() -> String:
	return _render(false)


## The line with colors for a RichTextLabel.
func bbcode() -> String:
	return _render(true)


func _render(colored: bool) -> String:
	var out := ""
	for p in parts:
		var piece := ""
		match p["kind"]:
			"term":
				piece = "%s %s" % [p["label"], _value(fmt(p["value"]), colored)]
			"num":
				piece = _value(fmt(p["value"]), colored)
			_:
				piece = _quiet(p["label"], colored)
		out = _join(out, piece, p)
	if result != null:
		var r := fmt(result)
		if not result_label.is_empty():
			r = "%s %s" % [r, result_label]
		out += " %s %s" % [_quiet("=", colored), _result(r, colored)]
	return out


## No space after "(" or before ")".
func _join(out: String, piece: String, p: Dictionary) -> String:
	if out.is_empty():
		return piece
	if p["kind"] == "op" and p["label"] == ")":
		return out + piece
	if out.ends_with("(") or out.ends_with("([/color]"):
		return out + piece
	return out + " " + piece


func _ops(s: String) -> void:
	for token in s.strip_edges().split(" ", false):
		var rest := token
		while not rest.is_empty():
			if rest.begins_with("(") or rest.begins_with(")"):
				op(rest[0])
				rest = rest.substr(1)
				continue
			var cut := rest.length()
			for b in ["(", ")"]:
				var at := rest.find(b)
				if at > 0:
					cut = mini(cut, at)
			var word := rest.substr(0, cut)
			if word.is_valid_float():
				num(int(word) if word.is_valid_int() else float(word))
			else:
				op(word)
			rest = rest.substr(cut)


static func _value(s: String, colored: bool) -> String:
	if not colored:
		return s
	return "[color=#%s]%s[/color]" % [FeelData.color(str(UiIcons.kit("tooltip.number_color", "text_bright"))).to_html(false), s]


static func _quiet(s: String, colored: bool) -> String:
	if not colored:
		return s
	return "[color=#%s]%s[/color]" % [UiStyle.role(str(UiIcons.kit("math.operator_role", "text_quiet"))).to_html(false), s]


static func _result(s: String, colored: bool) -> String:
	if not colored:
		return s
	return "[color=#%s]%s[/color]" % [UiStyle.role(str(UiIcons.kit("math.color_role", "hint"))).to_html(false), s]
