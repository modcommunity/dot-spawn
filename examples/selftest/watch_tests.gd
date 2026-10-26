extends "res://examples/selftest/selftest_base.gd"

## The mover watch and cull sections.


func _watch_rules() -> DotSpawnCullRules:
	var r := DotSpawnCullRules.new()
	r.enabled = true
	r.budget_usec = 0
	r.far_sec = 5.0
	return r


## Runs `seconds` of ticks; `mover` is (id, t) -> [position, has_goal]. Returns all verdicts.
func _drive(w: DotSpawnWatch, ids: Array, seconds: float, mover: Callable, cull: DotSpawnCull = null) -> Array[DotSpawnVerdict]:
	var all: Array[DotSpawnVerdict] = []
	var dt := 1.0 / RATE
	var t := 0.0

	while t < seconds:
		for id in ids:
			var m: Array = mover.call(id, t)
			w.report(id, m[0], &"common", m[1])

		var found := w.advance(dt)
		all.append_array(found)

		if cull != null:
			cull.process(found)

		t += dt

	return all


func _count(vs: Array[DotSpawnVerdict], id: Variant, category: int) -> int:
	var n := 0

	for v in vs:
		if v.id == id and v.category == category:
			n += 1

	return n


func _test_watch() -> void:
	_section("Mover watch")
	var off := DotSpawnWatch.new()
	_check(not off.rules.enabled, "off by default")
	off.report(1, Vector3.ZERO, &"common", true)
	_check(off.advance(10.0).is_empty(), "and a disabled watch finds nothing")

	var w := DotSpawnWatch.new(_watch_rules())
	var mover := func(id: Variant, t: float) -> Array:
		match id:
			"stuck": return [Vector3(1, 0, 1) + Vector3(0.1, 0, 0) * sin(t * 3.0), true]
			"idle": return [Vector3(5, 0, 5), false]
			"slow": return [Vector3(t * 0.5, 0, 9), true]
			"blocked": return [Vector3(2, 0, 2) if t < 2.5 else Vector3(2, 0, 2) + Vector3(t - 2.5, 0, 0), true]
			"fell": return [Vector3(0, -80, 0) if t > 1.0 else Vector3.ZERO, true]
			"nan": return [Vector3(NAN, 0, 0), true]
			"offnav": return [Vector3(40.0 + t * 0.3, 0, 40), true]
			"cutoff": return [Vector3(60, 0, 60) + Vector3(t, 0, 0), true]
			"lost": return [Vector3(200 + t, 0, 0), true]
		return [Vector3.ZERO, true]
	w.set_players(PackedVector3Array([Vector3(0, 0, 0)]))
	w.nav_distance_fn = func(p: Vector3) -> float: return 20.0 if p.x > 35.0 and p.x < 45.0 else 0.0
	w.reachable_fn = func(p: Vector3) -> bool: return not (p.x > 55.0 and p.x < 120.0)
	var ids := ["stuck", "idle", "slow", "blocked", "fell", "nan", "offnav", "cutoff", "lost"]
	var vs := _drive(w, ids, 12.0, mover)

	_check(_count(vs, "stuck", DotSpawnVerdict.Category.STUCK) > 0, "a mover with a goal that jitters in place is stuck")
	_check(_count(vs, "idle", DotSpawnVerdict.Category.STUCK) == 0, "a mover without a goal is never stuck")
	_check(_count(vs, "slow", DotSpawnVerdict.Category.STUCK) == 0, "a slow mover that keeps going is not stuck")
	_check(_count(vs, "blocked", DotSpawnVerdict.Category.STUCK) == 0, "one blocked for 2.5 s then freed is not stuck")
	_check(_count(vs, "fell", DotSpawnVerdict.Category.FELL_OUT) > 0, "below kill height fell out")
	_check(_count(vs, "nan", DotSpawnVerdict.Category.FELL_OUT) > 0, "a non-finite position fell out")
	_check(_count(vs, "offnav", DotSpawnVerdict.Category.OFF_NAV) > 0, "far from the navigation is off nav")
	_check(_count(vs, "cutoff", DotSpawnVerdict.Category.UNREACHABLE) > 0, "no path from any player is unreachable")
	_check(_count(vs, "lost", DotSpawnVerdict.Category.FAR) > 0, "far from every player for long is lost")
	_check(_count(vs, "idle", DotSpawnVerdict.Category.FAR) == 0, "one within reach of a player is not lost")
	_check(_count(vs, "blocked", DotSpawnVerdict.Category.OFF_NAV) == 0, "and nothing is off nav without a reading")
	_check(w.ever_stuck_count() == 1, "only the stuck mover is recorded as ever stuck")
	_check(w.kind_stats().has(&"common") and w.kind_stats()[&"common"]["stuck_sec"] > 0.0, "stuck seconds are kept per kind")
	_check(not w.worst_spots().is_empty(), "and the worst spots")
	_check(w.describe_lines().size() >= 3 and w.describe().contains("tracked"), "the watch describes itself")

	var before := w.tracked()
	w.forget("idle")
	w.forget("stuck")
	_check(w.tracked() == before - 2, "forgetting removes a mover")
	var more := _drive(w, ["slow", "blocked", "fell", "nan", "offnav", "cutoff", "lost"], 1.0, mover)
	_check(_count(more, "idle", DotSpawnVerdict.Category.STUCK) == 0 and w.tracked() == before - 2, "and the rest keep being sampled")

	var big := DotSpawnWatch.new(_watch_rules())
	var mover2 := func(id: Variant, t: float) -> Array:
		return [Vector3(float(id % 100) * 3.0, 0, float(id / 100) * 3.0 + t * 1.5), true]
	var many: Array = []
	for i in 1000:
		many.append(i)
	big.set_players(PackedVector3Array([Vector3.ZERO, Vector3(150, 0, 15)]))
	var t0 := Time.get_ticks_usec()
	var lost_count := _drive(big, many, 4.0, mover2).size()
	var per_tick := float(Time.get_ticks_usec() - t0) / (4.0 * RATE)
	_check(big.max_visited <= ceili(1000.0 / (RATE * 0.5)) + 1, "1000 movers: a tick samples only its share (%d)" % big.max_visited)
	_check(big.max_advance_usec < 2000, "1000 movers: the worst advance is under 2 ms (%d us)" % big.max_advance_usec)
	_check(per_tick < 3000.0, "1000 movers: report plus advance averages under 3 ms (%.0f us)" % per_tick)
	_check(big.samples >= 1000 * 3, "and every mover is still sampled each period (%d samples, %d verdicts)" % [big.samples, lost_count])

	var tight := _watch_rules()
	tight.budget_usec = 1
	var capped := DotSpawnWatch.new(tight)
	_drive(capped, many, 1.0, mover2)
	_check(capped.budget_trips > 0, "a tiny budget cuts a tick short and counts it")


func _test_cull() -> void:
	_section("Cull decisions")
	var rules := _watch_rules()
	var cull := DotSpawnCull.new(rules)
	var cat := DotSpawnVerdict.Category
	var act := DotSpawnDecision.Action

	var make := func(id: Variant, c: int, secs: float, t: float, kind: StringName = &"common") -> DotSpawnVerdict:
		var v := DotSpawnVerdict.new()
		v.id = id
		v.category = c
		v.seconds = secs
		v.time = t
		v.kind = kind
		v.position = Vector3(1, 0, 1)
		return v

	_check(DotSpawnCull.new().decide(make.call("a", cat.STUCK, 5.0, 0.0)).action == act.IGNORE, "a disabled cull ignores everything")
	_check(rules.fell_out_action == act.DESPAWN and rules.far_action == act.DESPAWN, "the default action is despawn, not kill")
	_check(cull.decide(make.call("f", cat.FELL_OUT, 0.0, 0.0)).action == act.DESPAWN, "fell out is despawned at once")

	var t := 10.0
	var first := cull.decide(make.call("s", cat.STUCK, 4.0, t))
	t += 2.5
	var second := cull.decide(make.call("s", cat.STUCK, 6.5, t))
	t += 2.5
	var third := cull.decide(make.call("s", cat.STUCK, 9.0, t))
	_check(first.action == act.NUDGE and second.action == act.NUDGE, "a stuck mover is nudged twice")
	_check(third.action == act.DESPAWN, "then despawned")

	var flap := cull.decide(make.call("s", cat.STUCK, 9.5, t + 0.5))
	_check(flap.action == act.IGNORE and flap.reason == "cooldown", "a second verdict inside the cooldown is ignored")

	rules.far_action = act.KILL
	rules.off_nav_action = act.TELEPORT
	rules.unreachable_action = act.IGNORE
	_check(cull.decide(make.call("l", cat.FAR, 20.0, 0.0)).action == act.KILL, "kill is a configurable action")
	_check(cull.decide(make.call("o", cat.OFF_NAV, 4.0, 0.0)).action == act.TELEPORT, "so is teleport")
	_check(cull.decide(make.call("u", cat.UNREACHABLE, 9.0, 0.0)).action == act.IGNORE, "and ignore, per category")

	rules.far_after_sec = 10.0
	_check(cull.decide(make.call("l2", cat.FAR, 5.0, 0.0)).reason == "not yet", "a category can wait longer than the watch")
	rules.far_after_sec = 0.0

	cull.seen_fn = func(_p: Vector3, id: Variant) -> bool: return id == "watched"
	_check(cull.decide(make.call("watched", cat.OFF_NAV, 4.0, 0.0)).reason == "seen", "a mover a player can see is not despawned or teleported")
	_check(cull.decide(make.call("hidden", cat.FAR, 20.0, 0.0)).action == act.KILL, "an unseen one is")
	_check(cull.decide(make.call("watched", cat.FELL_OUT, 0.0, 1.0)).action == act.DESPAWN, "a fall is removed even in view")

	rules.exempt_kinds = PackedStringArray(["boss"])
	_check(cull.decide(make.call("b", cat.FELL_OUT, 0.0, 0.0, &"boss")).reason == "exempt", "an exempt kind is left alone")

	var batch: Array[DotSpawnVerdict] = [make.call("m", cat.FAR, 20.0, 100.0), make.call("m", cat.FELL_OUT, 0.0, 100.0)]
	var picked := cull.process(batch)
	_check(picked.size() == 1 and picked[0].verdict.category == cat.FELL_OUT, "a batch yields one decision per mover, its worst")

	var log: Array = []
	cull.despawn_fn = func(id: Variant, _v: DotSpawnVerdict) -> void: log.append(id)
	var batch2: Array[DotSpawnVerdict] = [make.call("n", cat.FELL_OUT, 0.0, 200.0)]
	_check(cull.apply(cull.process(batch2)) == 1 and log == ["n"], "apply hands a decision to the host's callable")
	_check(cull.describe_lines().size() >= 2 and cull.describe().contains("despawn"), "the cull describes itself")

	var w := DotSpawnWatch.new(_watch_rules())
	var c2 := DotSpawnCull.new(w.rules)
	var removed: Array = []
	c2.despawn_fn = func(id: Variant, _v: DotSpawnVerdict) -> void:
		removed.append(id)
		w.forget(id)
	var nudged: Array = []
	c2.nudge_fn = func(id: Variant, _v: DotSpawnVerdict) -> void: nudged.append(id)
	var dt := 1.0 / RATE
	var elapsed := 0.0
	while elapsed < 30.0:
		if removed.is_empty():
			w.report("pinned", Vector3(3, 0, 3), &"common", true)

		c2.apply(c2.process(w.advance(dt)))
		elapsed += dt
	_check(nudged.size() == 2 and removed == ["pinned"], "end to end: a pinned mover is nudged twice, then despawned once (%d, %d)" % [nudged.size(), removed.size()])
