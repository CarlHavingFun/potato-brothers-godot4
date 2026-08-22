class_name GogoContentRegistry
extends RefCounted

var last_errors: Array[String] = []


func build_snapshot(packs: Array[GogoContentPackDefinition]) -> ContentSnapshot:
	last_errors.clear()
	if packs.is_empty():
		last_errors.append("no content packs supplied")
		return null
	var candidate := ContentSnapshot.new()
	var ordered := packs.duplicate()
	ordered.sort_custom(func(a: GogoContentPackDefinition, b: GogoContentPackDefinition) -> bool:
		if a.pack_kind == &"core" and b.pack_kind != &"core": return true
		if b.pack_kind == &"core" and a.pack_kind != &"core": return false
		return a.pack_id < b.pack_id
	)
	for pack in ordered:
		var error := candidate.install_pack(pack)
		if error != OK:
			last_errors.append("pack %s failed: %s" % [pack.pack_id if pack != null else &"<null>", error_string(error)])
			return null
	candidate.seal()
	return candidate
