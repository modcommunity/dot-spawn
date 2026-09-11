@tool
class_name DotSpawnMarker3D
extends Marker3D

## A place in a 3D level where something enters the world.
##
## Extends [Marker3D] rather than wrapping a [Node3D] so that it draws its own gizmo in
## the editor and a mapper can see which way it faces — which is the half of a spawn
## point that is invisible in code and obvious in a viewport, and the half that gets
## rotated ninety degrees by accident.
##
## The node's only job is to produce a [DotSpawnSite]. Everything that decides anything
## works on those, and nothing on this.

## What this site is called. A deathmatch map's forty points are all [code]&"any"[/code].
@export var site_id: StringName = &"any"

## Which team may use it. Empty means anybody.
@export var team: StringName = &""

## Which classes may use it. Empty means anybody.
@export var classes: Array[StringName] = []

## Higher wins a tie. A map's preferred start.
##
## Named to match [DotSpawnArea3D], where it cannot be called [code]priority[/code]
## because [Area3D] already has one.
@export var site_priority: int = 0

## A site switched off without deleting it. Still collected, still described.
@export var site_enabled: bool = true

## Ticks this site scores badly for after use. -1 takes the rules' default.
@export_range(-1, 100000, 1) var cooldown_ticks: int = -1

## Half-extents of a volume to pick a point inside. Zero is a bare point.
##
## [b]Set this on any map that spawns more than four things at once.[/b] Sixteen players
## entering a round at a point spawn are sixteen capsules in one place, and the engine's
## answer to that is to launch them.
@export var extents: Vector3 = Vector3.ZERO

## Whether standing here is safe, for a game that wants a protected area.
@export var protects: bool = false

## Anything a game mode wants to read: a zone, a lane, an objective id.
@export var meta: Dictionary = {}


## The value everything downstream works on.
##
## [b]Recomputed on every call rather than cached.[/b] A marker moved by an animation,
## a moving platform or a level script would otherwise hand out the place it used to be,
## and the symptom — players spawning where a lift was two minutes ago — reads as a
## netcode bug rather than as a stale cache.
func to_site() -> DotSpawnSite:
	var site := DotSpawnSite.new()
	site.id = site_id
	site.position = global_position
	site.yaw = global_basis.get_euler().y
	site.team = team
	site.classes = classes.duplicate()
	site.priority = site_priority
	site.enabled = site_enabled
	site.extents = extents
	site.cooldown_ticks = cooldown_ticks
	site.protects = protects
	site.meta = meta.duplicate(true)
	site.is_2d = false
	return site


func describe() -> String:
	return to_site().describe()


## Editor-time complaint about the one mistake that has no runtime symptom.
func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()

	if site_id == &"":
		out.append(
			"This marker has no site_id, so nothing can ask for it by name and a game "
			+ "mode that spawns teams separately cannot tell it apart."
		)

	if extents.x < 0.0 or extents.y < 0.0 or extents.z < 0.0:
		out.append(
			"Extents are half-sizes and must not be negative; a negative one samples "
			+ "the same range as its positive and reads as a typo that did nothing."
		)

	return out
