class_name AppContext
extends RefCounted


static func kernel(from_node: Node) -> AppKernel:
	if from_node == null or from_node.get_tree() == null:
		return null
	return from_node.get_tree().get_first_node_in_group(&"gogobro_app") as AppKernel
