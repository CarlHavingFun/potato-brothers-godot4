class_name CharacterSpriteDockLifecycle
extends RefCounted


var _emitter: Object
var _receiver: Callable = Callable()


func connect_files_dropped(emitter: Object, receiver: Callable) -> bool:
	if emitter == null or not receiver.is_valid() or not emitter.has_signal("files_dropped"):
		return false
	if _emitter == emitter and _receiver == receiver and emitter.is_connected("files_dropped", receiver):
		return false
	disconnect_files_dropped()
	var error := emitter.connect("files_dropped", receiver)
	if error != OK:
		return false
	_emitter = emitter
	_receiver = receiver
	return true


func disconnect_files_dropped() -> void:
	if _emitter != null and _receiver.is_valid() and _emitter.is_connected("files_dropped", _receiver):
		_emitter.disconnect("files_dropped", _receiver)
	_emitter = null
	_receiver = Callable()
