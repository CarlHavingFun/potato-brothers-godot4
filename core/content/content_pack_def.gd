class_name ContentPackDef
extends Resource


const CURRENT_API_VERSION := 2
const ContentPackDependencyResource := preload("res://core/content/content_pack_dependency.gd")

enum PackKind {
	CORE,
	CHARACTER,
	WEAPON,
}


@export var pack_id: StringName
@export var pack_version := "0.1.0"
@export var content_api_version := CURRENT_API_VERSION
@export var pack_kind := PackKind.CORE
@export var display_name_key: StringName
@export var dependencies: Array[ContentPackDependencyResource] = []
@export var characters: Array[CharacterDef]
@export var weapons: Array[WeaponDef]
@export var passives: Array[PassiveItemDef]
@export var upgrades: Array[UpgradeDef]
@export var enemies: Array[EnemyDef]
@export var waves: Array[WaveDef]
@export var difficulties: Array[DifficultyDef]
@export var translation_paths: Array[String]
