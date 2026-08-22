class_name BootResult
extends RefCounted

enum Status {
	OK,
	CONTENT_ERROR,
	SAVE_ERROR,
	SERVICE_ERROR,
}

var status: Status = Status.OK
var message: String = ""
var details: Array[String] = []


static func success() -> BootResult:
	return BootResult.new()


static func failure(next_status: Status, next_message: String, next_details: Array[String] = []) -> BootResult:
	var result := BootResult.new()
	result.status = next_status
	result.message = next_message
	result.details = next_details.duplicate()
	return result


func is_ok() -> bool:
	return status == Status.OK
