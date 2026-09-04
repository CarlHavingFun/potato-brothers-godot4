class_name GogoProfileJsonCodec
extends RefCounted

# Pure reader: keys/indices remain structured until diagnostics are formatted.
const MAX_DEPTH := 128
const MAX_TEXT_LENGTH := 8 * 1024 * 1024
const FLOAT_TAG := "@gogobro:f64:"
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


static func encode(value: Variant, domain: Callable = Callable()) -> Dictionary:
	var prepared := _prepare_exact_floats(value, domain, [], 0)
	if prepared.error != OK: return prepared
	return {
		"text": JSON.stringify(prepared.value, "\t", true, true),
		"error": OK,
		"path": "",
		"message": "",
	}


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


static func compare_exact_checkpoint_numbers(
	original: Variant,
	decoded: Variant,
	domain: Callable,
	segments: Array = [],
	path: String = "$",
	depth: int = 0
) -> Dictionary:
	if depth > MAX_DEPTH: return _error(path, "JSON nesting exceeds reader limit")
	if original is Dictionary:
		if not decoded is Dictionary or original.size() != decoded.size(): return _error(path, "encoded object shape changed")
		for key in original:
			if not decoded.has(key): return _error(path, "encoded object key changed")
			var check := compare_exact_checkpoint_numbers(
				original[key], decoded[key], domain, segments + [key], path + "." + str(key), depth + 1
			)
			if check.error != OK: return check
	elif original is Array:
		if not decoded is Array or original.size() != decoded.size(): return _error(path, "encoded array shape changed")
		for index in original.size():
			var check := compare_exact_checkpoint_numbers(
				original[index], decoded[index], domain, segments + [index], path + "[%d]" % index, depth + 1
			)
			if check.error != OK: return check
	elif typeof(original) == TYPE_INT:
		if typeof(decoded) != TYPE_INT or original != decoded: return _error(path, "encoded integer changed")
	elif typeof(original) == TYPE_FLOAT:
		if not is_finite(original): return _error(path, "nonfinite number")
		var numeric_domain := String(domain.call(segments)) if domain.is_valid() else ""
		if numeric_domain == "float" and (
			typeof(decoded) != TYPE_FLOAT or var_to_bytes(original) != var_to_bytes(decoded)
		):
			return _error(path, "encoded float changed from %s to %s" % [var_to_bytes(original), var_to_bytes(decoded)])
	elif typeof(original) in [TYPE_STRING, TYPE_STRING_NAME]:
		if typeof(decoded) not in [TYPE_STRING, TYPE_STRING_NAME] or String(original) != String(decoded):
			return _error(path, "encoded string changed")
	elif typeof(original) == TYPE_BOOL:
		if typeof(decoded) != TYPE_BOOL or original != decoded:
			return _error(path, "encoded boolean changed")
	elif original == null:
		if decoded != null:
			return _error(path, "encoded null changed")
	elif typeof(original) != typeof(decoded) or original != decoded:
		return _error(path, "encoded value changed")
	return {"error": OK, "path": "", "message": ""}


static func _prepare_exact_floats(value: Variant, domain: Callable, segments: Array, depth: int) -> Dictionary:
	if depth > MAX_DEPTH: return _error("$", "JSON nesting exceeds reader limit")
	if value is Dictionary:
		var object := {}
		for key in value:
			var child := _prepare_exact_floats(value[key], domain, segments + [key], depth + 1)
			if child.error != OK: return child
			object[key] = child.value
		return {"value": object, "error": OK, "path": "", "message": ""}
	if value is Array:
		var array := []
		for index in value.size():
			var child := _prepare_exact_floats(value[index], domain, segments + [index], depth + 1)
			if child.error != OK: return child
			array.append(child.value)
		return {"value": array, "error": OK, "path": "", "message": ""}
	if typeof(value) == TYPE_FLOAT and domain.is_valid() and String(domain.call(segments)) == "float":
		if not is_finite(value): return _error("$", "nonfinite number")
		return {"value": FLOAT_TAG + _float_hex(value), "error": OK, "path": "", "message": ""}
	return {"value": value, "error": OK, "path": "", "message": ""}


static func _float_hex(value: float) -> String:
	var encoded := PackedByteArray()
	encoded.resize(8)
	encoded.encode_double(0, value)
	var result := ""
	var digits := "0123456789abcdef"
	for index in encoded.size():
		var byte := int(encoded[index])
		result += digits.substr(byte >> 4, 1) + digits.substr(byte & 15, 1)
	return result


func _value(segments: Array, depth: int) -> Variant:
	_space()
	if not _failure.is_empty(): return null
	if depth > MAX_DEPTH: return _fail(segments, "JSON nesting exceeds reader limit")
	var token := _peek()
	if token == "{": return _object(segments, depth)
	if token == "[": return _array(segments, depth)
	if token == '"':
		var decoded_string: Variant = _string(segments)
		if not _failure.is_empty(): return null
		var numeric_domain := String(_domain.call(segments)) if _domain.is_valid() else ""
		if numeric_domain == "float" and String(decoded_string).begins_with(FLOAT_TAG):
			return _tagged_float(String(decoded_string), segments)
		return decoded_string
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


func _tagged_float(token: String, segments: Array) -> Variant:
	var hex := token.trim_prefix(FLOAT_TAG)
	if hex.length() != 16: return _fail(segments, "invalid exact float tag")
	var bytes := PackedByteArray()
	for offset in range(0, hex.length(), 2):
		var high := "0123456789abcdef".find(hex.substr(offset, 1).to_lower())
		var low := "0123456789abcdef".find(hex.substr(offset + 1, 1).to_lower())
		if high < 0 or low < 0: return _fail(segments, "invalid exact float tag")
		bytes.append(high * 16 + low)
	var value := bytes.decode_double(0)
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
