class_name DotSpawnPointSet
extends RefCounted

## The authored points of one map, versioned for saving.
##
## The map's own spawns are never edited: `apply_to` patches a map point by id (the def replaces it, so authored settings win), `enabled = false` switches one off, and an id the map lacks is added. An empty set leaves exactly what the map shipped.

var points: Array[DotSpawnPointDef] = []


func add(p: DotSpawnPointDef) -> void:
	points.append(p)


func find(id: StringName) -> DotSpawnPointDef:
	for p in points:
		if p.id == id:
			return p

	return null


func to_dict() -> Dictionary:
	var list: Array = []

	for p in points:
		list.append(p.to_dict())

	return {"version": DotSpawnPointDef.VERSION, "points": list}


## Refuses a newer version than this build knows; an older or missing one loads with defaults.
static func from_dict(d: Dictionary) -> DotResult:
	var v := int(d.get("version", 1))

	if v > DotSpawnPointDef.VERSION:
		return DotResult.fail(DotError.CODE_VERSION, "spawn point set version %d is newer than %d" % [v, DotSpawnPointDef.VERSION])

	var raw: Variant = d.get("points", [])

	if not (raw is Array):
		return DotResult.fail(DotError.CODE_INVALID, "points must be a list")

	var set := DotSpawnPointSet.new()
	var seen := {}

	for e: Variant in raw:
		if not (e is Dictionary):
			return DotResult.fail(DotError.CODE_INVALID, "a point must be a dictionary")

		var p := DotSpawnPointDef.from_dict(e)
		var bad := p.problem()

		if bad != "":
			return DotResult.fail(DotError.CODE_INVALID, "point '%s': %s" % [p.id, bad])

		if seen.has(p.id):
			return DotResult.fail(DotError.CODE_CONFLICT, "two points share the id '%s'" % p.id)

		seen[p.id] = true
		set.points.append(p)

	return DotResult.success(set)


## Applies the set to [param sites] (the map's own, left untouched as objects): a def with a map id replaces that site, any other is appended. Returns how many took effect.
func apply_to(sites: Array[DotSpawnSite], tick_rate: int = 64) -> int:
	var applied := 0

	for p in points:
		var s := p.to_site(tick_rate)
		var at := -1

		for i in sites.size():
			if sites[i].id == p.id:
				at = i
				break

		if at >= 0:
			sites[at] = s
		else:
			sites.append(s)

		applied += 1

	return applied
