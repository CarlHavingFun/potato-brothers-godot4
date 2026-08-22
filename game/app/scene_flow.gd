class_name SceneFlow
extends Node

signal route_changed(previous: StringName, current: StringName)
signal route_failed(route: StringName, error: Error)

var _host: Node
var _routes: Dictionary = {}
var _current_route: StringName = &""
var _current_scene: Node


func configure(host: Node, routes: Dictionary) -> void:
	_host = host
	_routes = routes.duplicate()


func open(route: StringName, payload: Dictionary = {}) -> Error:
	if _host == null or not is_instance_valid(_host):
		route_failed.emit(route, ERR_UNCONFIGURED)
		return ERR_UNCONFIGURED
	var packed: PackedScene = _routes.get(route)
	if packed == null:
		route_failed.emit(route, ERR_DOES_NOT_EXIST)
		return ERR_DOES_NOT_EXIST
	var candidate := packed.instantiate()
	if candidate == null:
		route_failed.emit(route, ERR_CANT_CREATE)
		return ERR_CANT_CREATE
	if candidate.has_method("receive_route_payload"):
		candidate.call("receive_route_payload", payload.duplicate(true))
	var previous := _current_route
	if _current_scene != null and is_instance_valid(_current_scene):
		_host.remove_child(_current_scene)
		_current_scene.queue_free()
	_host.add_child(candidate)
	_current_scene = candidate
	_current_route = route
	route_changed.emit(previous, route)
	return OK


func current_route() -> StringName:
	return _current_route
