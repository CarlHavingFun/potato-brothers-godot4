extends GdUnitTestSuite


const TEMP_ROOT := "user://tests/external_content_pack"
const SOURCE_MANIFEST := TEMP_ROOT + "/pack_source.tres"
const PACK_PATH := TEMP_ROOT + "/fixture_content.pck"
const VIRTUAL_MANIFEST := "res://content_packs/integration_fixture/pack.tres"
const DEFAULT_PACK_PATH := TEMP_ROOT + "/default_content.pck"
const DEFAULT_CONTENTS_PATH := TEMP_ROOT + "/default_content.contents.json"


func after_test() -> void:
	for path: String in [SOURCE_MANIFEST, PACK_PATH, DEFAULT_PACK_PATH, DEFAULT_CONTENTS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_catalog_loads_manifest_that_exists_only_inside_external_pck() -> void:
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	var live_copy_before := LocalizedTextService.resolve(&"ui.title.start")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_ROOT))
	var pack := ContentPackDef.new()
	pack.pack_id = &"integration_fixture"
	var character := CharacterDef.new()
	character.content_id = &"character/external"
	var default_character := Content.catalog.get_character(&"character/well_rounded")
	character.scene = default_character.scene
	character.stats = default_character.stats
	pack.characters = [character]
	assert_int(ResourceSaver.save(pack, SOURCE_MANIFEST)).is_equal(OK)

	var packer := PCKPacker.new()
	assert_int(packer.pck_start(ProjectSettings.globalize_path(PACK_PATH))).is_equal(OK)
	assert_int(packer.add_file(VIRTUAL_MANIFEST, ProjectSettings.globalize_path(SOURCE_MANIFEST))).is_equal(OK)
	assert_int(packer.flush()).is_equal(OK)
	assert_int(DirAccess.remove_absolute(ProjectSettings.globalize_path(SOURCE_MANIFEST))).is_equal(OK)
	assert_bool(FileAccess.file_exists(SOURCE_MANIFEST)).is_false()

	var loader := BootstrapContentLoader.new()
	assert_int(loader.mount_and_load(ProjectSettings.globalize_path(PACK_PATH), VIRTUAL_MANIFEST)).is_equal(OK)
	assert_object(loader.catalog.get_character(&"character/external")).is_not_null()
	assert_str(LocalizedTextService.resolve(&"ui.title.start")).is_equal(live_copy_before)
	loader.free()
	TranslationServer.set_locale(original_locale)


func test_generated_default_pck_contains_only_restricted_content_files() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_ROOT))
	var builder_script: Script = load("res://tools/content/build_content_pack.gd")
	var builder: Node = builder_script.new()
	var result: int = builder.call(
		"_build",
		"res://content_packs/default",
		"res://content_packs/default/pack.tres",
		DEFAULT_PACK_PATH,
		DEFAULT_CONTENTS_PATH
	)
	builder.free()
	assert_int(result).is_equal(OK)
	assert_bool(FileAccess.file_exists(DEFAULT_PACK_PATH)).is_true()
	var contents: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_CONTENTS_PATH))
	assert_bool(contents.get("replace_files", true)).is_false()
	assert_float(float(contents.get("schema_version", 0))).is_equal_approx(1.0, 0.001)
	assert_str(contents.get("pck_sha256", "")).is_equal(FileAccess.get_sha256(DEFAULT_PACK_PATH))
	var files: Array = contents.get("files", [])
	assert_bool(files.any(func(entry: Dictionary): return entry.path == "res://content_packs/default/pack.tres")).is_true()
	for entry: Dictionary in files:
		var path := String(entry.get("path", ""))
		assert_int(String(entry.get("sha256", "")).length()).is_equal(64)
		var allowed := path.begins_with("res://content_packs/default/") or path.begins_with("res://.godot/imported/")
		assert_bool(allowed).override_failure_message(path).is_true()
		assert_bool(path.contains("/assets/")).override_failure_message(path).is_false()
		assert_bool(path.begins_with("res://.godot/imported/")).override_failure_message(path).is_false()
		assert_bool(ContentValidator.FORBIDDEN_EXTENSIONS.has(path.get_extension().to_lower())).override_failure_message(path).is_false()
