extends "res://examples/selftest/watch_tests.gd"

## The strategies and spread section.


func _test_strategies() -> void:
	_section("Strategies and spread")
	var rules := DotSpawnRules.new()
	_check(rules.strategy == "map" and rules.validate().ok, "the default strategy is map and is valid")
	rules.strategy = "spread, nonsense"
	_check(not rules.validate().ok, "an unknown strategy name is refused")
	rules.strategy = "spread,map"
	_check(rules.strategies() == PackedStringArray(["spread", "map"]), "strategies are an ordered list")

	rules.strategy = "spread"
	rules.spread_distance = 10.0
	rules.spread_min = 5.0
	var d := _director(rules)

	for ix in range(5):
		for iz in range(4):
			d.add_site(DotSpawnSite.point(StringName("g%d_%d" % [ix, iz]), Vector3(ix * 10.0, 0.0, iz * 10.0)))

	var requests: Array[DotSpawnRequest] = []
	for i in range(8):
		requests.append(DotSpawnRequest.make("p%d" % i, &"", &"", 100))

	var res := d.choose_batch(requests)
	_check(res.ok and (res.value as Array).size() == 8, "a batch of 8 on 20 sites is answered")
	var min_gap := INF
	var picked: Array = res.value
	for i in range(picked.size()):
		for j in range(i + 1, picked.size()):
			min_gap = minf(min_gap, (picked[i] as DotSpawnChoice).transform.origin.distance_to((picked[j] as DotSpawnChoice).transform.origin))
	_check(min_gap >= rules.spread_distance, "the batch keeps every pair at least the spread distance apart (min %.1f)" % min_gap)

	var again := d.choose_batch(requests)
	var same := again.ok
	for i in range(8):
		same = same and (again.value[i] as DotSpawnChoice).site.id == (picked[i] as DotSpawnChoice).site.id
	_check(same, "the same batch on the same tick is the same answer")

	rules.strategy = "map"
	var plain := d.choose_batch(requests)
	_check(plain.ok and (plain.value as Array).size() == 8, "the map strategy still answers a batch")

	_strategy_grouped(rules, d)
	_strategy_floor(rules)
	_strategy_generated(d)
	_strategy_regroup()
	_strategy_one_site()


func _strategy_grouped(rules: DotSpawnRules, d: DotSpawnDirector) -> void:
	rules.generate = "off"
	rules.strategy = "grouped"
	rules.group_radius = 12.0
	var greqs: Array[DotSpawnRequest] = []
	for i in range(3):
		greqs.append(DotSpawnRequest.make("a%d" % i, &"red", &"", 200))
		greqs.append(DotSpawnRequest.make("b%d" % i, &"blue", &"", 200))
	var gres := d.choose_batch(greqs)
	_check(gres.ok and (gres.value as Array).size() == 6, "grouped: a batch of 6 (two teams of 3) on 20 sites is answered")
	var near_ok := true
	var ids := {}
	for team_ix in range(2):
		var anchor: Vector3 = (gres.value[team_ix] as DotSpawnChoice).transform.origin
		for k in range(3):
			var c: DotSpawnChoice = gres.value[team_ix + k * 2]
			ids[c.site.id] = true
			near_ok = near_ok and c.transform.origin.distance_to(anchor) <= rules.group_radius + 0.01
	_check(near_ok, "grouped: every member is within the radius of its team's anchor")
	_check(ids.size() == 6, "grouped: the six picks are six different sites")
	var ga: Vector3 = (gres.value[0] as DotSpawnChoice).transform.origin
	var gb: Vector3 = (gres.value[1] as DotSpawnChoice).transform.origin
	_check(ga.distance_to(gb) >= rules.spread_min, "grouped: the two anchors are apart")
	var gagain := d.choose_batch(greqs)
	var gsame := gagain.ok
	for i in range(6):
		gsame = gsame and (gagain.value[i] as DotSpawnChoice).site.id == (gres.value[i] as DotSpawnChoice).site.id
	_check(gsame, "grouped: the same batch on the same tick is the same answer")
	rules.group_radius = 1.0
	var tight := d.choose_batch(greqs)
	_check(tight.ok and (tight.value as Array).size() == 6, "grouped: a radius with no free site still answers (nearest unused)")
	_check(d.choose(DotSpawnRequest.make("solo", &"red", &"", 5)).ok, "grouped: a single choose outside a batch works")


func _strategy_floor(rules: DotSpawnRules) -> void:
	rules.strategy = "spread"
	rules.spread_distance = 20.0
	rules.spread_min = 20.0
	var fd := _director(rules)
	fd.add_site(DotSpawnSite.point(&"home", Vector3.ZERO))
	fd.add_site(DotSpawnSite.point(&"near", Vector3(5, 0, 0)))
	fd.add_site(DotSpawnSite.point(&"mid", Vector3(25, 0, 0)))
	fd.add_site(DotSpawnSite.point(&"far", Vector3(60, 0, 0)))
	var freqs: Array[DotSpawnRequest] = []
	freqs.append(DotSpawnRequest.make("f0", &"", &"", 300))
	freqs.append(DotSpawnRequest.make("f1", &"", &"", 300))
	var plain_farthest := true
	var site_pos := {&"home": Vector3.ZERO, &"near": Vector3(5, 0, 0), &"mid": Vector3(25, 0, 0), &"far": Vector3(60, 0, 0)}
	for t in range(40):
		freqs[1].tick = 300 + t
		freqs[0].tick = 300 + t
		var fr := fd.choose_batch(freqs)
		var q0: Vector3 = (fr.value[0] as DotSpawnChoice).transform.origin
		var q1: Vector3 = (fr.value[1] as DotSpawnChoice).transform.origin
		for pos in site_pos.values():
			plain_farthest = plain_farthest and q0.distance_to(pos) <= q0.distance_to(q1) + 0.01
	_check(plain_farthest, "floor off: spread always takes the farthest site from the first pick")
	rules.spread_floor_steers = true
	var meets := true
	for t in range(40):
		freqs[1].tick = 300 + t
		freqs[0].tick = 300 + t
		var fr2 := fd.choose_batch(freqs)
		var p0: Vector3 = (fr2.value[0] as DotSpawnChoice).transform.origin
		var p1: Vector3 = (fr2.value[1] as DotSpawnChoice).transform.origin
		meets = meets and p0.distance_to(p1) >= 20.0
	_check(meets, "floor on: every second pick meets the floor when a site does")
	rules.spread_distance = 500.0
	rules.spread_min = 500.0
	var fb := fd.choose_batch(freqs)
	_check(fb.ok and (fb.value[1] as DotSpawnChoice).site.id != (fb.value[0] as DotSpawnChoice).site.id, "floor on, none meets it: falls back to the farthest site")


func _strategy_generated(d: DotSpawnDirector) -> void:
	var rules := d.rules
	rules.strategy = "map"
	rules.spread_floor_steers = false
	rules.spread_distance = 10.0
	rules.spread_min = 5.0

	var calls := [0]
	d.generate_fn = func(count: int, _clearance: float, _map: String) -> Array:
		calls[0] += 1
		var out: Array = []
		for i in range(count):
			out.append(DotSpawnSite.point(StringName("gen%d" % i), Vector3(500.0 + i, 0.0, 0.0)))
		return out
	_check(d.ensure_generated("m", 1) == 0 and calls[0] == 0, "generation is off by default")
	rules.generate = "always"
	rules.generate_count = 6
	var added := d.ensure_generated("m", 1)
	var again_added := d.ensure_generated("m", 1)
	_check(added == 6 and again_added == 6 and calls[0] == 1 and d.sites().size() == 26, "generated sites are added once per map version, from the cache (%d calls)" % calls[0])
	rules.strategy = "map"
	var far_only := d.choose(DotSpawnRequest.make("x", &"", &"", 1))
	_check(far_only.ok and (far_only.value as DotSpawnChoice).site.source == &"map", "the map strategy never picks a generated site")
	rules.generate = "when_few"
	rules.generate_count = 10
	_check(d.ensure_generated("m", 1) == 0 and d.sites().size() == 20, "when_few generates nothing for a map with enough sites")

	rules.generate = "always"
	rules.generate_count = 4
	_check(d.ensure_generated("m", 1) == 4 and calls[0] == 2, "a changed generate_count is a new site set, not the cached one (%d calls)" % calls[0])
	rules.generate_clearance += 1.0
	d.ensure_generated("m", 1)
	_check(calls[0] == 3, "a changed generate_clearance regenerates (%d calls)" % calls[0])


func _strategy_regroup() -> void:
	var gr := DotSpawnRules.new()
	gr.strategy = "grouped"
	gr.group_radius = 15.0
	var gd := _director(gr)
	for site in _grid(20):
		gd.add_site(site)
	var all_ok := true
	for i in range(12):
		all_ok = all_ok and gd.choose(DotSpawnRequest.make("p%d" % i, &"red", &"", 7)).ok
	_check(all_ok, "grouped: per-player choose keeps answering past the anchor's free sites (it re-anchors)")
	_check((gd._group_taken[&"red"] as Array).size() <= 3 if gd._group_taken.has(&"red") else true, "grouped: taken ids expire instead of growing for ever")
	gd.choose(DotSpawnRequest.make("q", &"red", &"", 8))
	_check(not gd._group_anchors.is_empty(), "grouped: a per-player choose anchors a group")
	gd.reset_groups()
	_check(gd._group_anchors.is_empty() and gd._group_taken.is_empty(), "grouped: reset_groups forgets anchors and taken ids")
	gd.choose(DotSpawnRequest.make("q2", &"red", &"", 9))
	gd.refresh(false)
	_check(gd._group_anchors.is_empty(), "grouped: refresh forgets the anchors")


func _strategy_one_site() -> void:
	var sr := DotSpawnRules.new()
	sr.strategy = "spread"
	sr.spread_distance = 1000.0
	sr.spread_min = 0.0
	var sd := _director(sr)
	sd.add_site(DotSpawnSite.point(&"only", Vector3.ZERO))
	var sreqs: Array[DotSpawnRequest] = []
	sreqs.append(DotSpawnRequest.make("a", &"", &"", 1))
	sreqs.append(DotSpawnRequest.make("b", &"", &"", 1))
	var t0 := Time.get_ticks_usec()
	var sb := sd.choose_batch(sreqs)
	_check(sb.ok and Time.get_ticks_usec() - t0 < 200000, "spread: min 0 with every pick on one site answers without looping")
