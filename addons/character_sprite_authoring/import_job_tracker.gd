class_name CharacterSpriteImportJobTracker
extends RefCounted


const TERMINAL_STATES := ["complete", "complete_with_errors", "failed"]

var commands: Object
var active_job_id := ""


func track_import_result(command_result: Dictionary) -> bool:
	var value: Variant = command_result.get("result", command_result)
	if not value is Dictionary:
		return false
	var job_id := str((value as Dictionary).get("job_id", ""))
	if job_id.is_empty():
		return false
	active_job_id = job_id
	return true


func poll_import_job() -> Dictionary:
	if active_job_id.is_empty():
		return {"errors": PackedStringArray(["no active video sprite import job"])}
	if commands == null or not commands.has_method("poll_job"):
		return {"errors": PackedStringArray(["video sprite command runner is unavailable"])}
	var result: Dictionary = commands.call("poll_job", active_job_id) as Dictionary
	if str(result.get("state", "")) in TERMINAL_STATES:
		active_job_id = ""
	return result
