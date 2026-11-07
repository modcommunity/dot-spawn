class_name DotSpawnFlags
extends RefCounted

## Flag stands among a map's spawn sites: which sites are flags, which team each belongs to, and a fallback base per team for a map that has none.
##
## A flag spawn is a site of kind `flag` whose `team` is the team id as a number ("1", "2", "3"). Any number of teams may have one; a team's capture point is its own flag stand.


## Whether the site is a flag stand.
static func is_flag(site: DotSpawnSite) -> bool:
	return str(site.meta.get(DotSpawnPointDef.META_KIND, "")) == String(DotSpawnPointDef.KIND_FLAG)


## The site's team as a number, or 0 when it has none.
static func team_id(site: DotSpawnSite) -> int:
	var t := String(site.team)
	return int(t) if t.is_valid_int() else 0


## Every enabled flag stand.
static func flag_sites(sites: Array[DotSpawnSite]) -> Array[DotSpawnSite]:
	var out: Array[DotSpawnSite] = []

	for s in sites:
		if s.enabled and is_flag(s) and team_id(s) > 0:
			out.append(s)

	return out


## Every site a player may spawn on: flag stands left out.
static func player_sites(sites: Array[DotSpawnSite]) -> Array[DotSpawnSite]:
	var out: Array[DotSpawnSite] = []

	for s in sites:
		if not is_flag(s):
			out.append(s)

	return out


## team id -> the first enabled flag stand of that team.
static func flag_by_team(sites: Array[DotSpawnSite]) -> Dictionary:
	var out := {}

	for s in flag_sites(sites):
		var t := team_id(s)

		if not out.has(t):
			out[t] = s

	return out


## One base per team (team id -> DotSpawnSite) for [param team_count] teams: the map's flag stands where it has them, and for any team without one the member of that team's player spawns nearest their centre.
##
## A team with no tagged spawns takes a cluster: the untagged player spawns are split into as many groups as teams still need a base, seeded by farthest-point so two teams get opposite ends of the map. Returns fewer than [param team_count] only when there are not enough spawns to split.
static func bases(sites: Array[DotSpawnSite], team_count: int) -> Dictionary:
	var out := flag_by_team(sites)
	var pool: Array[DotSpawnSite] = []
	var untagged: Array[DotSpawnSite] = []

	for s in player_sites(sites):
		if not s.enabled:
			continue

		pool.append(s)
		var t := team_id(s)

		if t <= 0 or t > team_count:
			untagged.append(s)

	for t in range(1, team_count + 1):
		if out.has(t):
			continue

		var own: Array[DotSpawnSite] = []

		for s in pool:
			if team_id(s) == t:
				own.append(s)

		if not own.is_empty():
			out[t] = _medoid(own)

	var missing: Array[int] = []

	for t in range(1, team_count + 1):
		if not out.has(t):
			missing.append(t)

	if missing.is_empty() or untagged.size() < missing.size():
		return out

	var groups := _cluster(untagged, missing.size())

	for i in missing.size():
		if not groups[i].is_empty():
			out[missing[i]] = _medoid(groups[i])

	return out


static func _medoid(group: Array[DotSpawnSite]) -> DotSpawnSite:
	var centre := Vector3.ZERO

	for s in group:
		centre += s.position

	centre /= float(group.size())
	var best := group[0]

	for s in group:
		if s.position.distance_squared_to(centre) < best.position.distance_squared_to(centre):
			best = s

	return best


## Farthest-point seeding then a few rounds of nearest-seed assignment; deterministic, no random stream.
static func _cluster(sites: Array[DotSpawnSite], k: int) -> Array:
	var seeds: Array[Vector3] = []
	var west := sites[0]

	for s in sites:
		if s.position.x < west.position.x or (s.position.x == west.position.x and s.position.z < west.position.z):
			west = s

	var east := west

	for s in sites:
		if s.position.distance_squared_to(west.position) > east.position.distance_squared_to(west.position):
			east = s

	seeds.append(west.position)

	if k > 1:
		seeds.append(east.position)

	while seeds.size() < k:
		var pick := sites[0]
		var pick_d := -1.0

		for s in sites:
			var d := INF

			for c in seeds:
				d = minf(d, s.position.distance_squared_to(c))

			if d > pick_d:
				pick_d = d
				pick = s

		seeds.append(pick.position)

	var groups: Array = []

	for _round in 6:
		groups = []

		for i in k:
			groups.append([] as Array[DotSpawnSite])

		for s in sites:
			var bi := 0
			var bd := INF

			for i in k:
				var d := s.position.distance_squared_to(seeds[i])

				if d < bd:
					bd = d
					bi = i

			groups[bi].append(s)

		for i in k:
			var g: Array = groups[i]

			if g.is_empty():
				continue

			var c := Vector3.ZERO

			for s: DotSpawnSite in g:
				c += s.position

			seeds[i] = c / float(g.size())

	return groups
