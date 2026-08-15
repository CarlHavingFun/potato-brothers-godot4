class_name PresentationController
extends Node


signal semantic_state_changed(state: StringName)

const SEMANTIC_STATES: Array[StringName] = [
	&"idle", &"move", &"attack", &"hit", &"death", &"dash", &"spawn", &"telegraph",
]
const DEFAULT_ANIMATION_NAMES := {
	&"death": &"die",
}

@export var presentation_id: StringName
@export var state_animation_names: Dictionary = {}
@export var animation_player: AnimationPlayer
@export var animated_sprite: AnimatedSprite2D

var semantic_state: StringName = &""


func configure(
	target: Sprite2D,
	category: StringName,
	new_presentation_id: StringName,
	fallback: Texture2D = null
) -> bool:
	presentation_id = new_presentation_id
	var resolver := _resolver()
	state_animation_names = (
		resolver.resolve_animation_map(category, presentation_id)
		if resolver != null
		else {}
	)
	return apply_texture(target, category, fallback)


func set_semantic_state(state: StringName) -> bool:
	if state not in SEMANTIC_STATES:
		return false
	if semantic_state == state:
		return true
	semantic_state = state
	_play_mapped_animation(state)
	semantic_state_changed.emit(state)
	return true


func apply_texture(target: Sprite2D, category: StringName, fallback: Texture2D = null) -> bool:
	if target == null:
		return false
	var resolver := _resolver()
	var resolved := resolver.resolve_texture(category, presentation_id, fallback) if resolver != null else fallback
	if resolved == null:
		return false
	target.texture = resolved
	return true


func emit_cue(cue_id: StringName, context: Dictionary = {}) -> bool:
	var bus := get_node_or_null("/root/GameplayCues") as GameplayCueBus
	return bus.emit_cue(cue_id, context) if bus != null else false


func _play_mapped_animation(state: StringName) -> void:
	var mapped := StringName(str(
		state_animation_names.get(state, DEFAULT_ANIMATION_NAMES.get(state, state))
	))
	if animation_player != null and animation_player.has_animation(mapped):
		animation_player.play(mapped)
	elif animated_sprite != null and animated_sprite.sprite_frames != null \
	and animated_sprite.sprite_frames.has_animation(mapped):
		animated_sprite.play(mapped)


func _resolver() -> SkinResolver:
	return get_node_or_null("/root/Presentation") as SkinResolver
