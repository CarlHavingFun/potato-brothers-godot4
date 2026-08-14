extends GdUnitTestSuite


const PRODUCTION_ROOTS: Array[String] = [
	"res://autoloads",
	"res://core",
	"res://resources",
	"res://scenes",
]
const SOURCE_EXTENSIONS: Array[String] = ["gd", "tscn", "tres", "json"]
const FORBIDDEN_MARKERS: Array[String] = [
	"CloudSaveFile",
	"CloudID",
	"/saves/download",
	"/saves/upload",
	"/register/id",
]


func test_production_project_has_no_unity_legacy_cloud_dependency() -> void:
	var violations: Array[String] = []
	for root in PRODUCTION_ROOTS:
		_scan_directory(root, violations)

	assert_array(violations).is_empty()


func _scan_directory(path: String, violations: Array[String]) -> void:
	for file_name in DirAccess.get_files_at(path):
		if not SOURCE_EXTENSIONS.has(file_name.get_extension().to_lower()):
			continue
		var file_path := path.path_join(file_name)
		var contents := FileAccess.get_file_as_string(file_path)
		for marker in FORBIDDEN_MARKERS:
			if contents.contains(marker):
				violations.append("%s contains %s" % [file_path, marker])
	for directory_name in DirAccess.get_directories_at(path):
		_scan_directory(path.path_join(directory_name), violations)
