class_name DotSpawnOverrides
extends RefCounted

## Per-map spawn point edits an admin authors: the `spawn` profile kind, one profile per map id.
##
## The profile's `points` mapping holds id -> {pos, yaw, team, kind, enabled, weight, tags, removed}. An id the map already has is patched, any other id is a new `authored` point. Save writes the server tier, which is the exportable diff.

const ADDON := "dot_spawn"
const KIND := "spawn"
const AUTHORED := &"authored"


## The fields of a `spawn` profile.
static func schema() -> Array:
	return [DotProfileSet.field("points", "dict", {})]


## The profile set for a game's spawn overrides (`cfg/server/game/<game>/spawn/<map>.yml` over the game's).
static func make_set(game: String, roots: PackedStringArray = PackedStringArray(), cmdline: PackedStringArray = PackedStringArray()) -> DotProfileSet:
	var s := DotProfileSet.create(ADDON, game, KIND, schema())
	s.roots = roots
	s.cmdline = cmdline
	return s


## A site as an override entry.
static func entry_of(site: DotSpawnSite) -> Dictionary:
	var e := {
		"pos": [site.position.x, site.position.y, site.position.z],
		"yaw": site.yaw,
		"team": String(site.team),
		"enabled": site.enabled,
		"weight": site.weight,
		"tags": Array(site.tags),
	}
	var kind := str(site.meta.get(DotSpawnPointDef.META_KIND, ""))

	if kind != "" and kind != "both":
		e["kind"] = kind

	return e


## Patches [param site] with the keys [param e] holds; absent keys keep the site's value.
static func patch(site: DotSpawnSite, e: Dictionary) -> void:
	var pos: Variant = e.get("pos")

	if pos is Array and (pos as Array).size() == 3:
		site.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))

	if e.has("yaw"):
		site.yaw = float(e["yaw"])

	if e.has("team"):
		site.team = StringName(str(e["team"]))

	if e.has("enabled"):
		site.enabled = bool(e["enabled"])

	if e.has("weight"):
		site.weight = maxf(float(e["weight"]), 0.0)

	if e.has("kind"):
		site.meta[DotSpawnPointDef.META_KIND] = str(e["kind"])

	if e.has("tags") and e["tags"] is Array:
		var t := PackedStringArray()

		for x: Variant in e["tags"]:
			t.append(str(x))

		site.tags = t


## Applies [param points] (the profile's mapping) to [param sites]: patches, removals and additions. Returns how many entries took effect.
static func apply(sites: Array[DotSpawnSite], points: Dictionary) -> int:
	var by_id := {}

	for s in sites:
		by_id[String(s.id)] = s

	var applied := 0

	for key: Variant in points:
		var e: Variant = points[key]

		if not (e is Dictionary):
			continue

		var id := str(key)
		var entry: Dictionary = e

		if bool(entry.get("removed", false)):
			if by_id.has(id):
				sites.erase(by_id[id])
				by_id.erase(id)
				applied += 1

			continue

		if by_id.has(id):
			patch(by_id[id], entry)
			applied += 1
		elif entry.has("pos"):
			var added := DotSpawnSite.point(StringName(id), Vector3.ZERO)
			added.source = AUTHORED
			patch(added, entry)
			sites.append(added)
			by_id[id] = added
			applied += 1

	return applied
