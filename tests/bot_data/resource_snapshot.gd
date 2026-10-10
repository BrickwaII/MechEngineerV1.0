extends RefCounted
## Turns a Resource into plain nested data (dictionaries, arrays, values) by
## walking its stored properties, so two resources can be compared field by field.


static func of(value: Variant) -> Variant:
	if value is Resource:
		var fields := {"__script": value.get_script().resource_path if value.get_script() else ""}
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
				fields[property.name] = of(value.get(property.name))
		return fields
	if value is Array:
		return value.map(func(item: Variant) -> Variant: return of(item))
	if value is Dictionary:
		var copy := {}
		for key: Variant in value:
			copy[key] = of(value[key])
		return copy
	return value
