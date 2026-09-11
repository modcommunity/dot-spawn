class_name DotSpawnChoice
extends RefCounted

## Where something goes, which site that was, and whether the rules were satisfied.
##
## [b][member fell_back] is the field worth reading.[/b] A choice made against the rules
## is still a choice — a round where nobody spawns is indistinguishable from a crash to
## the player looking at it — but it is also a content bug, and one that is invisible
## unless something says so. The director logs it and emits a signal; this carries it to
## anybody who asked directly.

## The site that was picked. Never null in a successful result.
var site: DotSpawnSite = null

## Where to put the thing. Already sampled inside the site's area, if it has one.
var transform: Transform3D = Transform3D.IDENTITY

var tick: int = 0

## True when every site failed its conditions and the best rejected one was used.
var fell_back: bool = false

## Why, when [member fell_back]. Empty otherwise.
var reason: String = ""

## How many sites were in the pool, and how many passed.
var considered: int = 0
var allowed: int = 0

## Tick spawn protection runs out on, or the spawn tick when there is none.
var protected_until: int = 0


## The same answer for a 2D game.
func transform_2d() -> Transform2D:
	return Transform2D(
		transform.basis.get_euler().y,
		Vector2(transform.origin.x, transform.origin.y)
	)


func position() -> Vector3:
	return transform.origin


func site_id() -> StringName:
	return site.id if site != null else &""


func describe() -> String:
	return "%s at %s%s" % [
		String(site_id()),
		transform.origin,
		" (fell back: %s)" % reason if fell_back else "",
	]


func _to_string() -> String:
	return "DotSpawnChoice(%s)" % describe()
