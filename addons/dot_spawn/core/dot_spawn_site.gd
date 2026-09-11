class_name DotSpawnSite
extends RefCounted

## One candidate place to enter the world, as a value.
##
## [b]Everything in this addon that decides anything works on these, and nothing on a
## scene node.[/b] A [DotSpawnMarker3D] produces one, a [DotSpawnArea2D] produces one, a
## level generator produces one out of thin air — and from there the filtering, the
## scoring and the picking are pure functions over an array of values, which is what
## lets the whole selection half be tested with no world at all.
##
## Positions are [Vector3] even for a 2D game, with Z unused. One type rather than two
## avoids duplicating every scoring function, and [member is_2d] is what the conversion
## back to a [Transform2D] reads.

## The name this site is known by. Need not be unique; a deathmatch map has forty
## points all called [code]&"any"[/code] and that is the correct way to build one.
var id: StringName = &"any"

## Where. In 2D, X and Y are the pixel position and Z is unused.
var position: Vector3 = Vector3.ZERO

## Which way the spawned thing faces, in radians about the up axis.
var yaw: float = 0.0

## Which team may use it. [code]&""[/code] means anybody.
var team: StringName = &""

## Which classes may use it. Empty means anybody.
var classes: Array[StringName] = []

## Higher wins when two sites score the same. A map's "preferred" start.
var priority: int = 0

## A site a mapper or a game has switched off. Collected, ignored, and still described.
var enabled: bool = true

## Half-extents of the volume to pick a point inside. Zero is a point, not a volume.
##
## [b]The difference between a point and an area is the difference between a spawn that
## works for one player and a spawn that works for eight.[/b] Sixteen players entering a
## round at a point-spawn map are sixteen capsules in one place, and the engine's answer
## to that is to launch them.
var extents: Vector3 = Vector3.ZERO

## Whether this came from, and returns to, a 2D scene.
var is_2d: bool = false

## Ticks after a use during which this site scores badly. -1 uses the rules' default.
var cooldown_ticks: int = -1

## Whether standing here is safe. See [DotSpawnProtection].
var protects: bool = false

## Anything the game wants to carry along — a room id, a lane, an objective.
var meta: Dictionary = {}

## The tick this site was last used, or a large negative number for never.
##
## Kept on the site rather than in a side table because a site that is collected fresh
## from the scene every round would otherwise lose its history, and "spawn cooldowns
## reset when the map reloads" is correct while "spawn cooldowns reset when anything
## calls refresh" is a bug that only shows up under load.
var last_used_tick: int = -1000000

## How many things are standing on it right now, as the game last reported.
var occupants: int = 0


static func point(
	p_id: StringName,
	p_position: Vector3,
	p_yaw: float = 0.0,
	p_team: StringName = &""
) -> DotSpawnSite:
	var s := DotSpawnSite.new()
	s.id = p_id
	s.position = p_position
	s.yaw = p_yaw
	s.team = p_team
	return s


static func area(
	p_id: StringName,
	p_position: Vector3,
	p_extents: Vector3,
	p_team: StringName = &""
) -> DotSpawnSite:
	var s := point(p_id, p_position, 0.0, p_team)
	s.extents = p_extents
	return s


func is_area() -> bool:
	return extents.length_squared() > 0.0


## A place inside this site, deterministically, from the caller's stream.
##
## [b]The [RandomNumberGenerator] is a parameter and never a member.[/b] A site that
## rolls its own numbers is a site whose answer depends on how many times anything else
## rolled first, and this is called on a server that a client is predicting — so the
## same tick has to produce the same point on both machines or the player materialises
## somewhere they were not.
func sample(rng: RandomNumberGenerator) -> Transform3D:
	var origin := position

	if is_area() and rng != null:
		origin += Vector3(
			rng.randf_range(-extents.x, extents.x),
			rng.randf_range(-extents.y, extents.y),
			rng.randf_range(-extents.z, extents.z)
		)

	return Transform3D(Basis(Vector3.UP, yaw), origin)


## The same answer for a 2D game.
func sample_2d(rng: RandomNumberGenerator) -> Transform2D:
	var t := sample(rng)
	return Transform2D(yaw, Vector2(t.origin.x, t.origin.y))


func position_2d() -> Vector2:
	return Vector2(position.x, position.y)


## Whether this site is open to a given team and class at all.
##
## Filtering rather than scoring: a site restricted to the other side is not a bad
## choice, it is not a choice, and a scorer that merely penalises it will still pick it
## when it is the only one left.
func admits(p_team: StringName, p_class: StringName) -> bool:
	if not enabled:
		return false

	if team != &"" and p_team != &"" and team != p_team:
		return false

	if not classes.is_empty() and p_class != &"" and not classes.has(p_class):
		return false

	return true


func describe() -> String:
	return "%s at %s%s%s%s" % [
		String(id),
		("(%.1f, %.1f)" % [position.x, position.y]) if is_2d
			else ("(%.1f, %.1f, %.1f)" % [position.x, position.y, position.z]),
		"" if team == &"" else " team=%s" % String(team),
		" area" if is_area() else "",
		"" if enabled else " (disabled)",
	]


func duplicate_site() -> DotSpawnSite:
	var s := DotSpawnSite.new()
	s.id = id
	s.position = position
	s.yaw = yaw
	s.team = team
	s.classes = classes.duplicate()
	s.priority = priority
	s.enabled = enabled
	s.extents = extents
	s.is_2d = is_2d
	s.cooldown_ticks = cooldown_ticks
	s.protects = protects
	s.meta = meta.duplicate(true)
	s.last_used_tick = last_used_tick
	s.occupants = occupants
	return s


func _to_string() -> String:
	return "DotSpawnSite(%s)" % describe()
