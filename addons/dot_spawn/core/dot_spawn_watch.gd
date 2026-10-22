class_name DotSpawnWatch
extends RefCounted

## Finds movers that are stuck, off the navigation, fallen out, cut off or lost; decides nothing.

const CHANNEL := "spawn"
const SPOTS_KEPT := 64

var rules: DotSpawnCullRules = DotSpawnCullRules.new()
## (position: Vector3) -> float, metres from the navigation. Unset skips the off-nav verdict.
var nav_distance_fn: Callable = Callable()
## (position: Vector3) -> bool, whether any living player has a path to it. Unset skips unreachable.
var reachable_fn: Callable = Callable()
## The watch's clock, advanced by advance().
var now: float = 0.0
var samples: int = 0
var budget_trips: int = 0
var max_visited: int = 0
var last_advance_usec: int = 0
var max_advance_usec: int = 0

var _tracks: Dictionary = {}
var _order: Array = []
var _cursor: int = 0
var _players: PackedVector3Array = PackedVector3Array()
var _kinds: Dictionary = {}
var _spots: Dictionary = {}
var _ever_stuck: Dictionary = {}


class Track extends RefCounted:
	var index: int = 0
	var kind: StringName = &""
	var position: Vector3 = Vector3.ZERO
	var has_goal: bool = false
	var anchor: Vector3 = Vector3.ZERO
	var anchor_time: float = 0.0
	var last_sample: float = 0.0
	var last_probe: float = -1e9
	var off_nav_since: float = -1.0
	var unreachable_since: float = -1.0
	var far_since: float = -1.0
	var stuck_run: float = 0.0


func _init(p_rules: DotSpawnCullRules = null) -> void:
	if p_rules != null:
		rules = p_rules


## Positions of the living players, for the far and unreachable verdicts.
func set_players(positions: PackedVector3Array) -> void:
	_players = positions


## One mover's state this tick; call for every live mover, it only stores.
func report(id: Variant, position: Vector3, kind: StringName, has_goal: bool) -> void:
	var tr: Track = _tracks.get(id)

	if tr == null:
		tr = Track.new()
		tr.anchor = position
		tr.anchor_time = now
		tr.last_sample = now
		tr.index = _order.size()
		_order.append(id)
		_tracks[id] = tr

	tr.position = position
	tr.kind = kind
	tr.has_goal = has_goal


## Stop watching a mover that left the world.
func forget(id: Variant) -> void:
	var tr: Track = _tracks.get(id)

	if tr == null:
		return

	var last: Variant = _order.back()
	_order[tr.index] = last
	(_tracks[last] as Track).index = tr.index
	_order.pop_back()
	_tracks.erase(id)


func tracked() -> int:
	return _tracks.size()


## Advance the clock and sample this tick's share of movers; returns the verdicts found.
func advance(delta: float) -> Array[DotSpawnVerdict]:
	var out: Array[DotSpawnVerdict] = []
	now += delta

	if not rules.enabled or _order.is_empty():
		return out

	var t0 := Time.get_ticks_usec()
	var quota := ceili(float(_order.size()) * delta / rules.sample_sec) + 1

	if rules.max_per_tick > 0:
		quota = mini(quota, rules.max_per_tick)

	quota = mini(quota, _order.size())
	var visited := 0

	while visited < quota:
		if _cursor >= _order.size():
			_cursor = 0

		var tr: Track = _tracks[_order[_cursor]]
		var id: Variant = _order[_cursor]
		_cursor += 1
		visited += 1

		if now - tr.last_sample >= rules.sample_sec - 0.0001:
			_sample(id, tr, out)

		if rules.budget_usec > 0 and Time.get_ticks_usec() - t0 > rules.budget_usec:
			budget_trips += 1
			break

	max_visited = maxi(max_visited, visited)
	last_advance_usec = Time.get_ticks_usec() - t0
	max_advance_usec = maxi(max_advance_usec, last_advance_usec)
	return out


func _sample(id: Variant, tr: Track, out: Array[DotSpawnVerdict]) -> void:
	var dt := now - tr.last_sample
	tr.last_sample = now
	samples += 1
	var pos := tr.position

	if not pos.is_finite() or pos.y < rules.kill_y:
		out.append(_verdict(id, tr, DotSpawnVerdict.Category.FELL_OUT, 0.0))
		return

	var k: Dictionary = _kinds.get(tr.kind, {})

	if k.is_empty():
		k = {"goal_sec": 0.0, "stuck_sec": 0.0, "longest": 0.0}
		_kinds[tr.kind] = k

	if tr.has_goal:
		k["goal_sec"] += dt

	if not tr.has_goal or pos.distance_to(tr.anchor) > rules.stuck_radius:
		tr.anchor = pos
		tr.anchor_time = now
		tr.stuck_run = 0.0
	else:
		var held := now - tr.anchor_time

		if held >= rules.stuck_sec:
			k["stuck_sec"] += dt
			k["longest"] = maxf(k["longest"], held)
			_ever_stuck[id] = true
			_note_spot(pos)
			out.append(_verdict(id, tr, DotSpawnVerdict.Category.STUCK, held))

	if now - tr.last_probe >= rules.probe_sec:
		tr.last_probe = now

		if nav_distance_fn.is_valid():
			var off: bool = float(nav_distance_fn.call(pos)) > rules.off_nav_distance
			tr.off_nav_since = _since(tr.off_nav_since, off)

		if reachable_fn.is_valid() and not _players.is_empty():
			var blocked: bool = not bool(reachable_fn.call(pos))
			tr.unreachable_since = _since(tr.unreachable_since, blocked)

	if tr.off_nav_since >= 0.0 and now - tr.off_nav_since >= rules.off_nav_sec:
		out.append(_verdict(id, tr, DotSpawnVerdict.Category.OFF_NAV, now - tr.off_nav_since))

	if tr.unreachable_since >= 0.0 and now - tr.unreachable_since >= rules.unreachable_sec:
		out.append(_verdict(id, tr, DotSpawnVerdict.Category.UNREACHABLE, now - tr.unreachable_since))

	var lost := false

	if not _players.is_empty():
		lost = true

		for p in _players:
			if pos.distance_squared_to(p) <= rules.far_distance * rules.far_distance:
				lost = false
				break

	tr.far_since = _since(tr.far_since, lost)

	if tr.far_since >= 0.0 and now - tr.far_since >= rules.far_sec:
		out.append(_verdict(id, tr, DotSpawnVerdict.Category.FAR, now - tr.far_since))


func _since(since: float, bad: bool) -> float:
	if not bad:
		return -1.0

	return now if since < 0.0 else since


func _verdict(id: Variant, tr: Track, category: int, seconds: float) -> DotSpawnVerdict:
	var v := DotSpawnVerdict.new()
	v.id = id
	v.kind = tr.kind
	v.category = category
	v.seconds = seconds
	v.position = tr.position
	v.time = now
	return v


func _note_spot(pos: Vector3) -> void:
	var cell := Vector3(snappedf(pos.x, 4.0), 0.0, snappedf(pos.z, 4.0))

	if _spots.has(cell) or _spots.size() < SPOTS_KEPT:
		_spots[cell] = int(_spots.get(cell, 0)) + 1


## Seconds with a goal, seconds stuck and the longest stretch, per kind.
func kind_stats() -> Dictionary:
	return _kinds.duplicate(true)


func ever_stuck_count() -> int:
	return _ever_stuck.size()


## The worst stuck spots, rounded to 4 m, as [cell, count] pairs, worst first.
func worst_spots(limit: int = 5) -> Array:
	var pairs: Array = []

	for cell in _spots:
		pairs.append([cell, _spots[cell]])

	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return pairs.slice(0, limit)


func describe() -> String:
	return "DotSpawnWatch(%s, %d tracked, %d samples, %d budget trips, last %d us)" % [
		"on" if rules.enabled else "off", _tracks.size(), samples, budget_trips, last_advance_usec]


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray([describe()])
	lines.append("  ever stuck %d, max advance %d us, max visited %d" % [_ever_stuck.size(), max_advance_usec, max_visited])

	for kind in _kinds:
		var k: Dictionary = _kinds[kind]
		lines.append("  %s: goal %.1fs stuck %.1fs longest %.1fs" % [kind, k["goal_sec"], k["stuck_sec"], k["longest"]])

	for pair in worst_spots(3):
		lines.append("  spot %s x%d" % [(pair[0] as Vector3), pair[1]])

	return lines
