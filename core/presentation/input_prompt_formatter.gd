class_name InputPromptFormatter
extends RefCounted


static func format_binding_tokens(tokens: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for token: Dictionary in tokens:
		parts.append(format_token(token))
	return LocalizedTextService.resolve(&"input.binding.separator").join(parts)


static func format_token(token: Dictionary) -> String:
	var text_id := StringName(str(token.get("text_id", "input.unknown")))
	var args: Array = (token.get("args", []) as Array).duplicate()
	if token.has("axis_id"):
		var axis_id := StringName(str(token.get("axis_id", "input.axis.numbered")))
		var axis_text := LocalizedTextService.resolve(axis_id, args)
		var direction_text := LocalizedTextService.resolve(StringName(str(
			token.get("direction_id", "input.axis.positive")
		)))
		args = [axis_text, direction_text]
	var parts: Array[String] = []
	for raw_modifier: Variant in token.get("modifier_ids", []):
		parts.append(LocalizedTextService.resolve(StringName(str(raw_modifier))))
	parts.append(LocalizedTextService.resolve(text_id, args))
	return LocalizedTextService.resolve(&"input.binding.chord_separator").join(parts)
