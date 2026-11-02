class_name DotSpawnFloorSampler
extends RefCounted

## Spawn candidates for a map that has no spawn entities: floor points found by ray, spread over the whole level.
##
## Physics-free on purpose: the game passes `ray_fn`, so this runs over a trace, a navmesh query or a test grid.

const GENERATED := &"generated"


## `ray_fn(from: Vector3, to: Vector3) -> Dictionary` returns `{position, normal}` on a hit and `{}` on a miss. Returns [DotSpawnSite]s (id `gen_N`, source generated) chosen by farthest-point sampling, so every region of [param bounds] gets some.
static func sample(bounds: AABB, count: int, clearance: float, ray_fn: Callable, head_room: float = 1.9) -> Array[DotSpawnSite]:
	var out: Array[DotSpawnSite] = []

	if count <= 0 or not ray_fn.is_valid() or bounds.size.x <= 0.0 or bounds.size.z <= 0.0:
		return out

	var cands := _candidates(bounds, count * 12, clearance, head_room, ray_fn)

	if cands.is_empty():
		return out

	# Farthest-point sampling: start at the point nearest the middle, then keep taking the one furthest from all taken.
	var centre := bounds.get_center()
	var first := 0
	var best := INF

	for i in cands.size():
		var d := Vector2(cands[i].x - centre.x, cands[i].z - centre.z).length()

		if d < best:
			best = d
			first = i

	var nearest := PackedFloat32Array()
	nearest.resize(cands.size())
	nearest.fill(INF)
	var pick := first

	while out.size() < mini(count, cands.size()):
		var at: Vector3 = cands[pick]
		var site := DotSpawnSite.point(StringName("gen_%d" % out.size()), at, 0.0)
		site.source = GENERATED
		out.append(site)
		var far := -1.0
		var far_i := pick

		for i in cands.size():
			nearest[i] = minf(nearest[i], (cands[i] as Vector3).distance_to(at))

			if nearest[i] > far:
				far = nearest[i]
				far_i = i

		if far <= 0.0:
			break

		pick = far_i

	_face_open(out, cands)
	return out


static func _candidates(bounds: AABB, want: int, clearance: float, head_room: float, ray_fn: Callable) -> Array[Vector3]:
	var cells := maxi(want, 16)
	var step := maxf(sqrt(bounds.size.x * bounds.size.z / float(cells)), 0.5)
	var nx := int(ceil(bounds.size.x / step))
	var nz := int(ceil(bounds.size.z / step))
	var top := bounds.position.y + bounds.size.y
	var bottom := bounds.position.y
	var out: Array[Vector3] = []

	for ix in nx:
		for iz in nz:
			var x := bounds.position.x + (ix + 0.5) * step
			var z := bounds.position.z + (iz + 0.5) * step
			var hit: Variant = ray_fn.call(Vector3(x, top, z), Vector3(x, bottom, z))

			if not (hit is Dictionary) or (hit as Dictionary).is_empty():
				continue

			var normal: Vector3 = (hit as Dictionary).get("normal", Vector3.UP)

			if normal.y < 0.7:
				continue

			var at: Vector3 = (hit as Dictionary)["position"]

			if _is_clear(at, clearance, head_room, ray_fn):
				out.append(at)

	return out


static func _is_clear(at: Vector3, clearance: float, head_room: float, ray_fn: Callable) -> bool:
	var eye := at + Vector3(0.0, 0.1, 0.0)
	var up: Variant = ray_fn.call(eye, at + Vector3(0.0, head_room, 0.0))

	if up is Dictionary and not (up as Dictionary).is_empty():
		return false

	if clearance <= 0.0:
		return true

	var chest := at + Vector3(0.0, 0.9, 0.0)

	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var side: Variant = ray_fn.call(chest, chest + (dir as Vector3) * clearance)

		if side is Dictionary and not (side as Dictionary).is_empty():
			return false

	return true


## Turns each site towards the far side of the map, so a spawner does not face a wall.
static func _face_open(sites: Array[DotSpawnSite], cands: Array[Vector3]) -> void:
	for s in sites:
		var far := 0.0
		var yaw := 0.0

		for c in cands:
			var flat := Vector2(c.x - s.position.x, c.z - s.position.z)

			if flat.length() > far:
				far = flat.length()
				yaw = atan2(-flat.x, -flat.y)

		s.yaw = yaw
