class_name DotSpawnScoring
extends RefCounted
## The pure half of site choice: scoring, tie-breaking and the scatter draw. [DotSpawnDirector] keeps the state and passes it in.

## Random over every site by weight, damped near recent picks and living enemies.
##
## Priority is ignored on purpose: a "preferred" start is what put every bot in the default area. Sight is tested by rejection on the drawn site, so the cost is a few rays, not sites times enemies.
static func pick_scatter(
	rules: DotSpawnRules,
	recent: Array[Vector3],
	pool: Array[DotSpawnSite],
	context: Dictionary,
	rng: RandomNumberGenerator
) -> DotSpawnSite:
	var enemies: Array = context.get("enemies", [])
	var weights := PackedFloat64Array()
	var total := 0.0

	for site in pool:
		var w := maxf(site.weight, 0.0)

		if w > 0.0:
			w *= scatter_damping(rules, recent, site.position, enemies)

		weights.append(w)
		total += w

	if total <= 0.0:
		# Every site is taken: draw by weight alone rather than leave somebody unplaced.
		for i in pool.size():
			weights[i] = maxf(pool[i].weight, 0.0)
			total += weights[i]

	if total <= 0.0:
		return null

	var can_see: Variant = context.get("can_see", null)
	var checks: bool = can_see is Callable and (can_see as Callable).is_valid() and not enemies.is_empty() and rules.scatter_seen_factor < 1.0
	var drawn: DotSpawnSite = null

	for attempt in 8:
		var roll := rng.randf() * total
		var idx := weights.size() - 1

		for i in weights.size():
			roll -= weights[i]

			if roll <= 0.0 and weights[i] > 0.0:
				idx = i
				break

		drawn = pool[idx]

		if not checks or not seen_by_any(drawn.position, enemies, can_see as Callable):
			return drawn

		if rng.randf() < rules.scatter_seen_factor:
			return drawn

	return drawn


static func scatter_damping(rules: DotSpawnRules, recent: Array[Vector3], at: Vector3, enemies: Array) -> float:
	var f := 1.0

	if rules.scatter_min_gap > 0.0:
		if nearest_to(at, enemies) < rules.scatter_min_gap or nearest_to(at, recent) < rules.scatter_min_gap:
			return 0.0

	if rules.scatter_radius > 0.0:
		var near := INF

		for r in recent:
			near = minf(near, at.distance_to(r))

		if near < rules.scatter_radius:
			f *= 0.02 + 0.98 * (near / rules.scatter_radius)

	if rules.scatter_enemy_radius > 0.0:
		var e_near := nearest_to(at, enemies)

		if e_near < rules.scatter_enemy_radius:
			var t := e_near / rules.scatter_enemy_radius
			f *= 0.01 + 0.99 * t * t

	return f


static func nearest_to(at: Vector3, points: Array) -> float:
	var nearest := INF

	for p: Variant in points:
		nearest = minf(nearest, at.distance_to(p as Vector3))

	return nearest


static func seen_by_any(at: Vector3, enemies: Array, can_see: Callable) -> bool:
	for e: Variant in enemies:
		if bool(can_see.call(e as Vector3, at)):
			return true

	return false


## Highest scorer, with ties broken by priority and then by id.
##
## Deterministic ties: scene-tree order differs between a client and a server that loaded the level differently.
static func best(pool: Array[DotSpawnSite], scorer: Callable) -> DotSpawnSite:
	var best: DotSpawnSite = null
	var best_score := -INF

	for site in pool:
		var s := float(scorer.call(site))

		if best == null or s > best_score:
			best = site
			best_score = s
			continue

		if is_equal_approx(s, best_score):
			if site.priority > best.priority:
				best = site
			elif site.priority == best.priority and String(site.id) < String(best.id):
				best = site

	return best


static func score(rules: DotSpawnRules, conditions: Array[DotSpawnCondition], site: DotSpawnSite, context: Dictionary) -> float:
	var score := float(site.priority) * rules.priority_weight

	var enemies: Array = context.get("enemies", [])
	var friends: Array = context.get("friends", [])

	var enemy_d := nearest_distance(site, enemies)
	if enemy_d < INF:
		score += enemy_d * rules.enemy_distance_weight

	var friend_d := nearest_distance(site, friends)
	if friend_d < INF:
		score += friend_d * rules.friend_distance_weight

	var tick := int(context.get("tick", 0))
	var cooldown := site.cooldown_ticks if site.cooldown_ticks >= 0 else rules.cooldown_ticks

	if cooldown > 0 and tick - site.last_used_tick < cooldown:
		score -= rules.cooldown_penalty

	score -= rules.occupancy_penalty * float(site.occupants)

	var can_see: Variant = context.get("can_see", null)

	if can_see is Callable and (can_see as Callable).is_valid():
		for e: Variant in enemies:
			if bool((can_see as Callable).call(e as Vector3, site.position)):
				score -= rules.visible_penalty
				break

	for condition in conditions:
		if condition != null and condition.enabled:
			score += condition.bonus(site, context)

	return score


## Distance to the nearest of a set of points, or INF when the set is empty.
##
## INF, not zero: an empty list means "no information", and zero would make every site equally terrible.
static func nearest_distance(site: DotSpawnSite, points: Array) -> float:
	var nearest := INF

	for p: Variant in points:
		var d := site.position.distance_to(p as Vector3)
		if d < nearest:
			nearest = d

	return nearest
