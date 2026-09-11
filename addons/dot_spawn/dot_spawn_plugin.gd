@tool
extends EditorPlugin

## Editor entry point for dot-spawn. Registers inspector types only.
##
## No autoloads: a listen server runs a director for the game it is hosting and another
## for the one it is previewing, which is the case an autoload forbids.

const _ICON := "res://addons/dot_spawn/icon_placeholder.svg"

const _TYPES := [
	["DotSpawnDirector", "Node", "res://addons/dot_spawn/runtime/dot_spawn_director.gd"],
	["DotSpawnMarker3D", "Marker3D", "res://addons/dot_spawn/nodes/dot_spawn_marker_3d.gd"],
	["DotSpawnMarker2D", "Marker2D", "res://addons/dot_spawn/nodes/dot_spawn_marker_2d.gd"],
	["DotSpawnArea3D", "Area3D", "res://addons/dot_spawn/nodes/dot_spawn_area_3d.gd"],
	["DotSpawnArea2D", "Area2D", "res://addons/dot_spawn/nodes/dot_spawn_area_2d.gd"],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
