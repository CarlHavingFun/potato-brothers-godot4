extends GdUnitTestSuite


const InstallerScript := preload("res://core/content/content_pack_installer.gd")
const TEST_ROOT := "user://tests/content_pack_installer"
const SOURCE_PCK := TEST_ROOT + "/source.pck"
const DESCRIPTOR := TEST_ROOT + "/source.contents.json"


func before_test() -> void:
	_cleanup_tree()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ROOT))
	var file := FileAccess.open(SOURCE_PCK, FileAccess.WRITE)
	file.store_buffer("fixture-pck".to_utf8_buffer())
	file.close()
	_write_descriptor(FileAccess.get_sha256(SOURCE_PCK))


func after_test() -> void:
	_cleanup_tree()


func test_installs_and_replaces_an_unmounted_pack_transactionally() -> void:
	var installer := InstallerScript.new(TEST_ROOT.path_join("installed"))
	var result: Dictionary = installer.install(SOURCE_PCK, DESCRIPTOR)
	assert_bool(result.ok).is_true()
	assert_bool(result.restart_required).is_false()
	assert_bool(FileAccess.file_exists(result.pck_path)).is_true()
	assert_int(installer.installed_entries().size()).is_equal(1)


func test_rejects_hash_and_pack_root_violations_without_installing() -> void:
	var installer := InstallerScript.new(TEST_ROOT.path_join("installed"))
	_write_descriptor("0".repeat(64))
	var hash_result: Dictionary = installer.install(SOURCE_PCK, DESCRIPTOR)
	assert_bool(hash_result.ok).is_false()
	assert_array(installer.installed_entries()).is_empty()
	_write_descriptor(FileAccess.get_sha256(SOURCE_PCK), "res://core/escape")
	var root_result: Dictionary = installer.install(SOURCE_PCK, DESCRIPTOR)
	assert_bool(root_result.ok).is_false()
	assert_array(installer.installed_entries()).is_empty()


func test_mounted_update_and_remove_are_staged_for_restart() -> void:
	var installer := InstallerScript.new(TEST_ROOT.path_join("installed"))
	assert_bool(installer.install(SOURCE_PCK, DESCRIPTOR).ok).is_true()
	installer.mark_mounted(&"character_fixture")
	var update: Dictionary = installer.install(SOURCE_PCK, DESCRIPTOR)
	assert_bool(update.ok).is_true()
	assert_bool(update.restart_required).is_true()
	var removal: Dictionary = installer.remove(&"character_fixture")
	assert_bool(removal.ok).is_true()
	assert_bool(removal.restart_required).is_true()


func _write_descriptor(hash: String, root := "res://content_packs/characters/fixture") -> void:
	var file := FileAccess.open(DESCRIPTOR, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"schema_version": 1,
		"pack_id": "character_fixture",
		"pack_version": "1.0.0",
		"content_api_version": ContentPackDef.CURRENT_API_VERSION,
		"manifest_virtual_path": root.path_join("pack.tres"),
		"source_root_virtual_path": root,
		"pck_sha256": hash,
		"replace_files": false,
		"files": [{"path": root.path_join("pack.tres"), "sha256": "1".repeat(64)}],
	}))
	file.close()


func _cleanup_tree() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	if DirAccess.dir_exists_absolute(absolute):
		_remove_directory(absolute)


func _remove_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for entry: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(entry))
	for child: String in directory.get_directories():
		_remove_directory(path.path_join(child))
	DirAccess.remove_absolute(path)
