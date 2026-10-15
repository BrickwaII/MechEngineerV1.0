class_name CliOptions
extends RefCounted
## Command line options for the tools' entry scripts: `--name value` pairs
## over a set of defaults.
##
##   var opts := CliOptions.parse(args, {"runs": "200", "seed": "1"}, USAGE)
##   if opts.is_empty():
##       return 1   # the problem and the usage were printed


## `defaults` with each `--key value` in `args` laid over it. An unknown key
## or a key with no value prints the problem (and `usage`, when given) and
## gives {}.
static func parse(args: PackedStringArray, defaults: Dictionary, usage := "") -> Dictionary:
	var opts := defaults.duplicate()
	var i := 0
	while i < args.size():
		var key := args[i].trim_prefix("--")
		if not opts.has(key) or i + 1 >= args.size():
			printerr("Unknown or incomplete option: %s" % args[i])
			if not usage.is_empty():
				printerr(usage)
			return {}
		opts[key] = args[i + 1]
		i += 2
	return opts


## Fight or campaign switches from "decision=option,decision=option" laid
## over `into`. Returns false, printing `what` and the bad pair, when a pair
## has no "=".
static func parse_choices(text: String, into: Dictionary, what := "--set wants") -> bool:
	for pair in text.split(",", false):
		if not "=" in pair:
			printerr("%s decision=option, got %s" % [what, pair])
			return false
		into[pair.get_slice("=", 0).strip_edges()] = pair.get_slice("=", 1).strip_edges()
	return true
