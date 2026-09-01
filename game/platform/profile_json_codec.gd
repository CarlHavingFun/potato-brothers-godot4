class_name GogoProfileJsonCodec
extends RefCounted

# Pure reader: keys/indices remain structured until diagnostics are formatted.
const MAX_DEPTH := 128
const MAX_TEXT_LENGTH := 8 * 1024 * 1024
var _text := ""
var _offset := 0
var _domain := Callable()
var _failure := {}


static func decode(text: String, domain: Callable = Callable()) -> Dictionary:
	# Explicit self-load also works before the editor has indexed this new class_name.
	var reader = (load("res://game/platform/profile_json_codec.gd") as GDScript).new()
	reader._text = text
	reader._domain = domain
	if text.length() > MAX_TEXT_LENGTH: return _error("$", "profile JSON exceeds reader limit")
	var value: Variant = reader._value([], 0)
	reader._space()
	if reader._offset != text.length(): reader._fail([], "trailing JSON input")
	if not reader._failure.is_empty(): return reader._failure
	return {"value": value, "error": OK, "path": "", "message": ""}


static func compare_integers(original: Variant, decoded: Variant, path: String = "$", depth: int = 0) -> Dictionary:
	if depth > MAX_DEPTH: return _error(path, "JSON nesting exceeds reader limit")
	if original is Dictionary:
		if not decoded is Dictionary or original.size() != decoded.size(): return _error(path, "encoded object shape changed")
		for key in original:
			if not decoded.has(key): return _error(path, "encoded object key changed")
			var check := compare_integers(original[key], decoded[key], path + "." + str(key), depth + 1)
			if check.error != OK: return check
	elif original is Array:
		if not decoded is Array or original.size() != decoded.size(): return _error(path, "encoded array shape changed")
		for index in original.size():
			var check := compare_integers(original[index], decoded[index], path + "[%d]" % index, depth + 1)
			if check.error != OK: return check
	elif typeof(original) == TYPE_INT:
		if typeof(decoded) != TYPE_INT or original != decoded: return _error(path, "encoded integer changed")
	elif typeof(original) == TYPE_FLOAT:
		if not is_finite(original): return _error(path, "nonfinite number")
	return {"error": OK, "path": "", "message": ""}


func _value(segments: Array, depth: int) -> Variant:
	_space()
	if not _failure.is_empty(): return null
	if depth > MAX_DEPTH: return _fail(segments, "JSON nesting exceeds reader limit")
	var token := _peek()
	if token == "{": return _object(segments, depth)
	if token == "[": return _array(segments, depth)
	if token == '"': return _string(segments)
	for pair in [["true", true], ["false", false], ["null", null]]:
		if _text.substr(_offset, pair[0].length()) == pair[0]:
			_offset += pair[0].length()
			return pair[1]
	if token == "-" or _digit(token): return _number(segments)
	return _fail(segments, "expected JSON value")


func _object(segments: Array, depth: int) -> Variant:
	_offset += 1
	_space()
	var result := {}
	if _take("}"): return result
	while _failure.is_empty():
		if _peek() != '"': return _fail(segments, "expected object key")
		var key: Variant = _string(segments)
		if not _failure.is_empty(): return null
		var child := segments + [key]
		if result.has(key): return _fail(child, "duplicate object key")
		_space()
		if not _take(":"): return _fail(child, "expected colon")
		result[key] = _value(child, depth + 1)
		_space()
		if _take("}"): return result
		if not _take(","): return _fail(child, "expected object separator")
		_space()
	return null


func _array(segments: Array, depth: int) -> Variant:
	_offset += 1
	_space()
	var result := []
	if _take("]"): return result
	while _failure.is_empty():
		result.append(_value(segments + [result.size()], depth + 1))
		_space()
		if _take("]"): return result
		if not _take(","): return _fail(segments, "expected array separator")
	return null


func _string(segments: Array) -> Variant:
	_offset += 1
	var result := ""
	while _offset < _text.length():
		var character := _peek()
		_offset += 1
		if character == '"': return result
		if character.unicode_at(0) < 32: return _fail(segments, "unescaped control character")
		if character != "\\":
			result += character
			continue
		var escape := _peek()
		_offset += 1
		var escapes := {'"': '"', "\\": "\\", "/": "/", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t"}
		if escapes.has(escape):
			result += escapes[escape]
			continue
		if escape != "u": return _fail(segments, "invalid string escape")
		var code := _hex4(segments)
		if code >= 0xD800 and code <= 0xDBFF:
			if _text.substr(_offset, 2) != "\\u": return _fail(segments, "missing low surrogate")
			_offset += 2
			var low := _hex4(segments)
			if low < 0xDC00 or low > 0xDFFF: return _fail(segments, "invalid low surrogate")
			code = 0x10000 + (code - 0xD800) * 1024 + low - 0xDC00
		elif code >= 0xDC00 and code <= 0xDFFF:
			return _fail(segments, "unpaired low surrogate")
		if not _failure.is_empty(): return null
		result += String.chr(code)
	return _fail(segments, "unterminated string")


func _hex4(segments: Array) -> int:
	var value := 0
	for index in 4:
		var digit := "0123456789abcdef".find(_peek().to_lower()) if not _peek().is_empty() else -1
		if digit < 0:
			_fail(segments, "invalid Unicode escape")
			return 0
		value = value * 16 + digit
		_offset += 1
	return value


func _number(segments: Array) -> Variant:
	var start := _offset
	var negative := _take("-")
	var digits := ""
	if _take("0"):
		digits = "0"
		if _digit(_peek()): return _fail(segments, "leading zero")
	else:
		while _digit(_peek()):
			digits += _peek()
			_offset += 1
		if digits.is_empty(): return _fail(segments, "missing integer digits")
	var fractional_places := 0
	var plain_integer := true
	if _take("."):
		plain_integer = false
		while _digit(_peek()):
			digits += _peek()
			_offset += 1
			fractional_places += 1
		if fractional_places == 0: return _fail(segments, "missing fraction digits")
	var exponent := 0
	if _take("e") or _take("E"):
		plain_integer = false
		var exponent_negative := _take("-")
		if not exponent_negative: _take("+")
		if not _digit(_peek()): return _fail(segments, "missing exponent digits")
		# Beyond text length + 400, saturation cannot change int64 proof or finite doubles.
		while _digit(_peek()):
			exponent = mini(_text.length() + 400, exponent * 10 + int(_peek()))
			_offset += 1
		if exponent_negative: exponent = -exponent
	var domain := String(_domain.call(segments)) if _domain.is_valid() else ""
	var significant := digits.lstrip("0")
	if significant.is_empty(): return 0
	var shift := exponent - fractional_places
	while significant.ends_with("0"):
		significant = significant.left(-1)
		shift += 1
	if shift >= 0 and significant.length() + shift <= 19:
		var magnitude := significant + "0".repeat(shift)
		var limit := "9223372036854775808" if negative else "9223372036854775807"
		if magnitude.length() < 19 or magnitude <= limit:
			# Negative accumulation represents INT64_MIN without overflowing its magnitude.
			var exact := 0
			for digit in magnitude: exact = exact * 10 - int(digit)
			return exact if negative else -exact
	if domain == "integer" or (plain_integer and domain != "float"):
		return _fail(segments, "expected exact bounded integer")
	# Finite float fields retain rounding and underflow, without admitting them as integers.
	var decimal_order := significant.length() + shift - 1
	if decimal_order > 308: return _fail(segments, "nonfinite number")
	if decimal_order < -324: return -0.0 if negative else 0.0
	var value := _text.substr(start, _offset - start).to_float()
	if not is_finite(value): return _fail(segments, "nonfinite number")
	return value


func _space() -> void:
	while _peek() in [" ", "\t", "\n", "\r"]: _offset += 1


func _peek() -> String:
	return _text.substr(_offset, 1)


func _take(token: String) -> bool:
	if _peek() != token: return false
	_offset += 1
	return true


static func _digit(character: String) -> bool:
	return character.length() == 1 and character >= "0" and character <= "9"


func _fail(segments: Array, message: String) -> Variant:
	if _failure.is_empty():
		var path := "$"
		for segment in segments: path += "[%d]" % segment if segment is int else "." + String(segment)
		_failure = _error(path, message)
	return null


static func _error(path: String, message: String) -> Dictionary:
	return {"value": null, "error": ERR_FILE_CORRUPT, "path": path, "message": message}
