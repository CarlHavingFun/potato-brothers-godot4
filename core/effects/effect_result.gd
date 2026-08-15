class_name EffectResult
extends RefCounted


var applied_effect_ids: Array[StringName] = []
var stat_changes: Dictionary = {}
var healing: float = 0.0
var extra_damage: float = 0.0
var pierce: int = 0
var bounce: int = 0
var status_commands: Array[Dictionary] = []
var area_commands: Array[Dictionary] = []
var projectile_commands: Array[Dictionary] = []
var summon_commands: Array[Dictionary] = []
var building_commands: Array[Dictionary] = []
var emitted_events: Array[GameplayEventContext] = []
var processed_event_count: int = 0
var recursion_blocked := false
