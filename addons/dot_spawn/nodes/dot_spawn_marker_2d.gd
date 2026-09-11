@tool
class_name DotSpawnMarker2D
extends Marker2D

## A place in a 2D level where something enters the world.
##
## The 2D half of [DotSpawnMarker3D], and deliberately a separate class rather than one
## node that branches: a [Marker2D] and a [Marker3D] cannot share a base below [Node],
## the editor gizmos are different, and a single node that guessed would guess wrong in
## the scene where it mattered.
##
## The site it produces carries the 2D position in X and Y with Z unused, which is what
## lets one selector serve both.

@export var site_id: StringName = &"any"

@export var team: StringName = &""

@export var classes: Array[StringName] = []

## Higher wins a tie. A map's preferred start.
##
## Named to match [DotSpawnArea3D], where it cannot be called [code]priority[/code]
## because [Area3D] already has one.
@export var site_priority: int = 0

@export var site_enabled: bool = true

@export_range(-1, 100000, 1) var cooldown_ticks: int = -1

## Half-extents in pixels. Zero is a bare point.
@export var extents: Vector2 = Vector2.ZERO

@export var protects: bool = false

@export var meta: Dictionary = {}


func to_site() -> DotSpawnSite:
	var site := DotSpawnSite.new()
	site.id = site_id
	site.position = Vector3(global_position.x, global_position.y, 0.0)
	site.yaw = global_rotation
	site.team = team
	site.classes = classes.duplicate()
	site.priority = site_priority
	site.enabled = site_enabled
	site.extents = Vector3(extents.x, extents.y, 0.0)
	site.cooldown_ticks = cooldown_ticks
	site.protects = protects
	site.meta = meta.duplicate(true)
	site.is_2d = true
	return site


func describe() -> String:
	return to_site().describe()


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()

	if site_id == &"":
		out.append("This marker has no site_id, so nothing can ask for it by name.")

	if extents.x < 0.0 or extents.y < 0.0:
		out.append("Extents are half-sizes and must not be negative.")

	return out
