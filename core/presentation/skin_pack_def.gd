class_name SkinPackDef
extends Resource


const CURRENT_API_VERSION := 2
const LEGACY_API_VERSION := 1
const ASSET_CATEGORIES: Array[StringName] = [
	&"character",
	&"enemy",
	&"weapon/icon",
	&"weapon/world",
	&"projectile/world",
	&"passive/icon",
	&"upgrade/icon",
	&"pickup/world",
	&"prop/world",
	&"ally/world",
	&"scene/background",
	&"scene/floor",
	&"ui/logo",
	&"ui/app_icon",
	&"ui/fallback",
]
const DEFAULT_VARIANTS := {
	&"weapon": &"world",
	&"projectile": &"world",
	&"passive": &"icon",
	&"upgrade": &"icon",
	&"pickup": &"world",
	&"prop": &"world",
	&"ally": &"world",
	&"scene": &"background",
	&"ui": &"fallback",
}
const LEGACY_CATEGORY_ALIASES := {
	&"passive": &"pickup",
	&"upgrade": &"pickup",
}

@export var skin_id: StringName
@export var skin_version := "0.1.0"
@export var skin_api_version := CURRENT_API_VERSION
@export var product_name := "GOBRO"
@export var logo: Texture2D
@export var background: Texture2D
@export var theme: Theme
@export var font: Font
@export var translation_paths: PackedStringArray = []
@export var accent_color := Color.WHITE
@export var asset_tables: Dictionary = {}
@export var fallback_asset_paths: Dictionary = {}
@export var animation_maps: Dictionary = {}
@export var audio_cues: Dictionary = {}
@export var music_tracks: Dictionary = {}
@export var particle_cues: Dictionary = {}
@export var screen_shake_cues: Dictionary = {}
@export var rumble_cues: Dictionary = {}
@export var feedback_profiles: Dictionary = {}


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if skin_id.is_empty():
		errors.append("skin_id is required")
	if skin_api_version != CURRENT_API_VERSION:
		errors.append("unsupported skin_api_version: %d" % skin_api_version)
		return errors
	if product_name.strip_edges().is_empty():
		errors.append("product_name is required")
	for translation_path: String in translation_paths:
		if translation_path.is_empty() or not ResourceLoader.exists(translation_path):
			errors.append("missing skin translation catalog: %s" % translation_path)
	for category: StringName in ASSET_CATEGORIES:
		var fallback_path := str(fallback_asset_paths.get(category, ""))
		if fallback_path.is_empty() or not ResourceLoader.exists(fallback_path):
			errors.append("missing fallback asset for %s" % category)
	var invalid_cues := _invalid_semantic_keys(audio_cues)
	invalid_cues.append_array(_invalid_semantic_keys(particle_cues))
	for cue_id: String in invalid_cues:
		errors.append("invalid semantic cue: %s" % cue_id)
	_validate_cue_paths(audio_cues, "audio", errors)
	_validate_cue_paths(particle_cues, "particle", errors)
	for raw_track_id: Variant in music_tracks:
		var track_path := str(music_tracks[raw_track_id])
		if track_path.is_empty() or not ResourceLoader.exists(track_path):
			errors.append("missing music track: %s" % raw_track_id)
	return errors


func asset_path(
	category: StringName,
	presentation_id: StringName,
	variant: StringName = &""
) -> String:
	var qualified := qualified_category(category, variant)
	var exact := _exact_asset_path(qualified, presentation_id)
	if not exact.is_empty():
		return exact

	# V1 manifests stored every visual form in one flat category. Keep those
	# tables readable for migration and tooling, while validate() deliberately
	# rejects them as release manifests.
	var legacy := legacy_category(qualified)
	if legacy != qualified:
		exact = _exact_asset_path(legacy, presentation_id)
		if not exact.is_empty():
			return exact

	var fallback_path := _fallback_path(qualified)
	if not fallback_path.is_empty():
		return fallback_path
	if legacy != qualified:
		fallback_path = _fallback_path(legacy)
		if not fallback_path.is_empty():
			return fallback_path
	if String(qualified).begins_with("ui/") and qualified != &"ui/fallback":
		fallback_path = _fallback_path(&"ui/fallback")
	return fallback_path


static func qualified_category(category: StringName, variant: StringName = &"") -> StringName:
	var raw_category := String(category).strip_edges()
	if raw_category.is_empty() or raw_category.contains("/"):
		return StringName(raw_category)
	var resolved_variant := variant
	if resolved_variant.is_empty():
		resolved_variant = StringName(str(DEFAULT_VARIANTS.get(category, "")))
	if resolved_variant.is_empty():
		return StringName(raw_category)
	return StringName("%s/%s" % [raw_category, String(resolved_variant).strip_edges()])


static func legacy_category(category: StringName) -> StringName:
	var base := String(category).get_slice("/", 0)
	return StringName(str(LEGACY_CATEGORY_ALIASES.get(StringName(base), base)))


func _exact_asset_path(category: StringName, presentation_id: StringName) -> String:
	var table: Variant = asset_tables.get(category, asset_tables.get(String(category), {}))
	if table is not Dictionary:
		return ""
	var exact := str(table.get(presentation_id, table.get(String(presentation_id), "")))
	return exact if not exact.is_empty() and ResourceLoader.exists(exact) else ""


func _fallback_path(category: StringName) -> String:
	var path := str(
		fallback_asset_paths.get(category, fallback_asset_paths.get(String(category), ""))
	)
	return path if not path.is_empty() and ResourceLoader.exists(path) else ""


func cue_definition(cue_id: StringName) -> Dictionary:
	return {
		"audio": str(audio_cues.get(cue_id, audio_cues.get(String(cue_id), ""))),
		"particle": str(particle_cues.get(cue_id, particle_cues.get(String(cue_id), ""))),
		"screen_shake": screen_shake_cues.get(cue_id, screen_shake_cues.get(String(cue_id), {})),
		"rumble": rumble_cues.get(cue_id, rumble_cues.get(String(cue_id), {})),
		"feedback": feedback_profiles.get(cue_id, feedback_profiles.get(String(cue_id), {})),
	}


func music_path(track_id: StringName) -> String:
	var path := str(music_tracks.get(track_id, music_tracks.get(String(track_id), "")))
	return path if ResourceLoader.exists(path) else ""


func _invalid_semantic_keys(values: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for raw_key: Variant in values:
		if not GameplayCueBus.is_semantic_id(StringName(str(raw_key))):
			result.append(str(raw_key))
	return result


func _validate_cue_paths(values: Dictionary, kind: String, errors: PackedStringArray) -> void:
	for raw_cue_id: Variant in values:
		var path := str(values[raw_cue_id])
		if path.is_empty() or not ResourceLoader.exists(path):
			errors.append("missing %s cue asset: %s" % [kind, raw_cue_id])
