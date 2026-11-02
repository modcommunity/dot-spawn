extends "res://examples/selftest/strategy_tests.gd"

## The free-for-all scatter strategy, team filtering, authored overrides and the floor sampler.


func _grid_director(rules: DotSpawnRules) -> DotSpawnDirector:
	var d := _director(rules)

	# A 10 x 10 grid over 100 m; the first 10 sites (a 30 m corner) are the "default area" with the top priority.
	for ix in 10:
		for iz in 10:
			var s := DotSpawnSite.point(StringName("g%d_%d" % [ix, iz]), Vector3(ix * 10.0 + 5.0, 0.0, iz * 10.0 + 5.0))
			s.priority = 10 if ix < 3 and iz < 3 else 0
			d.add_site(s)

	return d


func _test_scatter() -> void:
	_section("Scatter: free-for-all spreads over the whole map")
	var rules := DotSpawnRules.deathmatch()
	_check(rules.strategy == "scatter,map" and rules.validate().ok, "the deathmatch preset scatters and is valid")
	var d := _grid_director(rules)
	var regions := {}
	var in_default := 0
	var total := 400

	for i in total:
		var res := d.choose(DotSpawnRequest.make("p%d" % (i % 24), &"", &"", i * 7))
		var o: Vector3 = (res.value as DotSpawnChoice).transform.origin
		regions[Vector2i(int(o.x / 25.0), int(o.z / 25.0))] = true

		if o.x < 30.0 and o.z < 30.0:
			in_default += 1

	_check(regions.size() == 16, "every one of the 16 map regions is used in %d spawns (%d)" % [total, regions.size()])
	var share := float(in_default) / float(total)
	_check(share <= 0.16, "the high-priority default corner (9 of 100 sites) gets %.0f%% of spawns, not the majority" % (share * 100.0))

	var d2 := _grid_director(rules)
	var res_a := d2.choose(DotSpawnRequest.make("bot1", &"", &"", 5))
	var d3 := _grid_director(rules)
	var res_b := d3.choose(DotSpawnRequest.make("bot1", &"", &"", 5))
	_check((res_a.value as DotSpawnChoice).site.id == (res_b.value as DotSpawnChoice).site.id, "the same request on a fresh director is the same site")

	var recent_gap := INF
	var last: Vector3 = Vector3(1e6, 0.0, 1e6)
	var d4 := _grid_director(rules)
	var near_repeat := 0

	for i in 60:
		var o4: Vector3 = (d4.choose(DotSpawnRequest.make("q", &"", &"", i)).value as DotSpawnChoice).transform.origin
		recent_gap = minf(recent_gap, o4.distance_to(last)) if i > 0 else recent_gap
		near_repeat += 1 if o4.distance_to(last) < 1.0 else 0
		last = o4

	_check(near_repeat == 0, "no site is picked twice running (%d repeats)" % near_repeat)

	_test_scatter_batches(rules)
	_test_scatter_enemies(rules)


func _test_scatter_batches(rules: DotSpawnRules) -> void:
	var db := _grid_director(rules)
	var placed: Array = []
	db.enemies_fn = func(_t: StringName, _k: String) -> Array: return placed
	var used := {}
	var shared := 0
	var per_site := {}

	for i in 32:
		var cb := db.choose(DotSpawnRequest.make("b%d" % i, &"", &"", 900)).value as DotSpawnChoice
		placed.append(cb.transform.origin)
		shared += 1 if used.has(cb.site.id) else 0
		used[cb.site.id] = true

	_check(shared == 0, "32 players spawning on one tick share no point (%d shared)" % shared)

	for r in 40:
		placed.clear()

		for i in 32:
			var cr := db.choose(DotSpawnRequest.make("b%d" % i, &"", &"", 1000 + r)).value as DotSpawnChoice
			placed.append(cr.transform.origin)
			per_site[cr.site.id] = int(per_site.get(cr.site.id, 0)) + 1

	var most := 0

	for k in per_site:
		most = maxi(most, int(per_site[k]))

	_check(most <= 1280 * 4 / 100, "over 40 batches no point takes more than 4%% of spawns (%d of 1280)" % most)
	_check(per_site.size() >= 90, "over 40 batches nearly every one of the 100 points is used (%d)" % per_site.size())


func _test_scatter_enemies(rules: DotSpawnRules) -> void:
	var seen := _grid_director(rules)
	var enemy := Vector3(55.0, 0.0, 55.0)
	seen.enemies_fn = func(_t: StringName, _k: String) -> Array: return [enemy]
	var close := 0

	for i in 200:
		var o5: Vector3 = (seen.choose(DotSpawnRequest.make("v%d" % (i % 9), &"", &"", i * 3)).value as DotSpawnChoice).transform.origin
		close += 1 if o5.distance_to(enemy) < rules.scatter_enemy_radius else 0

	_check(close <= 16, "spawns within %.0f m of a living enemy are rare (%d of 200)" % [rules.scatter_enemy_radius, close])

	var blind := _grid_director(rules)
	blind.enemies_fn = func(_t: StringName, _k: String) -> Array: return [Vector3(5.0, 1.0, 5.0)]
	blind.can_see_fn = func(_from: Vector3, to: Vector3) -> bool: return to.x < 50.0
	var visible := 0

	for i in 200:
		var o6: Vector3 = (blind.choose(DotSpawnRequest.make("w%d" % (i % 9), &"", &"", i * 5)).value as DotSpawnChoice).transform.origin
		visible += 1 if o6.x < 50.0 else 0

	_check(visible <= 30, "sites an enemy can see are mostly skipped (%d of 200)" % visible)


func _test_team_filter() -> void:
	_section("Scatter: team, enabled and weight filtering")
	var d := _director(DotSpawnRules.deathmatch())
	var red := DotSpawnSite.point(&"red1", Vector3(0.0, 0.0, 0.0), 0.0, &"red")
	var blue := DotSpawnSite.point(&"blue1", Vector3(50.0, 0.0, 0.0), 0.0, &"blue")
	var any := DotSpawnSite.point(&"any1", Vector3(0.0, 0.0, 50.0))
	var off := DotSpawnSite.point(&"off1", Vector3(50.0, 0.0, 50.0))
	off.enabled = false
	var zero := DotSpawnSite.point(&"zero1", Vector3(25.0, 0.0, 25.0))
	zero.weight = 0.0

	for s in [red, blue, any, off, zero]:
		d.add_site(s)

	var red_ok := true
	var blue_ok := true
	var ffa_ids := {}
	var hidden := true

	for i in 120:
		var r := (d.choose(DotSpawnRequest.make("r", &"red", &"", i)).value as DotSpawnChoice).site.id
		var b := (d.choose(DotSpawnRequest.make("b", &"blue", &"", i)).value as DotSpawnChoice).site.id
		var f := (d.choose(DotSpawnRequest.make("f", &"", &"", i)).value as DotSpawnChoice).site.id
		red_ok = red_ok and (r == &"red1" or r == &"any1")
		blue_ok = blue_ok and (b == &"blue1" or b == &"any1")
		ffa_ids[f] = true
		hidden = hidden and f != &"off1" and f != &"zero1" and r != &"zero1" and b != &"zero1"

	_check(red_ok, "red spawns only on red and any-team points")
	_check(blue_ok, "blue spawns only on blue and any-team points")
	_check(ffa_ids.has(&"red1") and ffa_ids.has(&"blue1") and ffa_ids.has(&"any1"), "a team-less (FFA) request reaches every enabled point")
	_check(hidden, "disabled and zero-weight points are never picked")
	_check(red.duplicate_site().weight == 1.0 and zero.duplicate_site().weight == 0.0, "weight survives duplicate_site")


func _flat_ray(from: Vector3, to: Vector3) -> Dictionary:
	if from.y <= to.y or from.x != to.x or from.z != to.z:
		return {}

	if from.x > 60.0 and from.x < 90.0 and from.z > 60.0 and from.z < 90.0:
		return {}

	return {"position": Vector3(from.x, 0.0, from.z), "normal": Vector3.UP}


func _test_floor_sampler() -> void:
	_section("Floor sampler: generated spawn candidates")
	var bounds := AABB(Vector3(0.0, -2.0, 0.0), Vector3(120.0, 20.0, 120.0))
	var made := DotSpawnFloorSampler.sample(bounds, 40, 1.0, _flat_ray)
	_check(made.size() == 40, "asks for 40 and gets 40 (%d)" % made.size())
	var quads := {}
	var in_hole := 0
	var ids := {}

	for s in made:
		quads[Vector2i(int(s.position.x / 60.0), int(s.position.z / 60.0))] = true
		ids[s.id] = true

		if s.position.x > 60.0 and s.position.x < 90.0 and s.position.z > 60.0 and s.position.z < 90.0:
			in_hole += 1

	_check(quads.size() == 4, "all four quarters of the map get candidates (%d)" % quads.size())
	_check(in_hole == 0, "nothing lands where there is no floor")
	_check(ids.size() == made.size() and made[0].source == &"generated", "ids are unique and marked generated")
	_check(DotSpawnFloorSampler.sample(bounds, 5, 1.0, Callable()).is_empty(), "no ray function yields nothing, not an error")

	var rules := DotSpawnRules.deathmatch()
	rules.generate = "when_few"
	rules.generate_count = 24
	var d := _director(rules)
	d.add_site(DotSpawnSite.point(&"only", Vector3(1.0, 0.0, 1.0)))
	d.generate_fn = func(count: int, clearance: float, _map: String) -> Array: return DotSpawnFloorSampler.sample(bounds, count, clearance, _flat_ray)
	var added := d.ensure_generated("m1")
	_check(added == 24 and d.sites().size() == 25, "a map with one site is topped up to 24 generated candidates (%d)" % added)
	var far := 0

	for i in 100:
		var o: Vector3 = (d.choose(DotSpawnRequest.make("g%d" % (i % 7), &"", &"", i * 11)).value as DotSpawnChoice).transform.origin
		far += 1 if o.distance_to(Vector3(1.0, 0.0, 1.0)) > 20.0 else 0

	_check(far >= 85, "scatter uses the generated candidates, not only the lone map site (%d of 100)" % far)


func _test_overrides() -> void:
	_section("Overrides: authored spawn points per map")
	var sites: Array[DotSpawnSite] = [
		DotSpawnSite.point(&"a", Vector3(0.0, 0.0, 0.0)),
		DotSpawnSite.point(&"b", Vector3(10.0, 0.0, 0.0)),
		DotSpawnSite.point(&"c", Vector3(20.0, 0.0, 0.0)),
	]
	var points := {
		"a": {"team": "red", "weight": 3.0, "tags": ["roof"], "pos": [1.0, 2.0, 3.0], "yaw": 1.5},
		"b": {"removed": true},
		"n1": {"pos": [5.0, 0.0, 5.0], "team": "blue", "enabled": false},
		"ghost": {"removed": true},
		"bad": {"team": "x"},
	}
	var n := DotSpawnOverrides.apply(sites, points)
	_check(n == 3, "patch, removal and addition took effect, a ghost and a position-less addition did not (%d)" % n)
	_check(sites.size() == 3 and sites[0].team == &"red" and sites[0].weight == 3.0 and sites[0].position == Vector3(1.0, 2.0, 3.0), "an edited point carries team, weight, position")
	_check(sites[0].tags == PackedStringArray(["roof"]) and is_equal_approx(sites[0].yaw, 1.5), "tags and facing are set")
	_check(sites[2].id == &"n1" and sites[2].source == &"authored" and not sites[2].enabled and sites[2].team == &"blue", "an added point is authored with its properties")

	var tmp := ProjectSettings.globalize_path("user://spawn_override_test_%d" % Time.get_ticks_usec())
	var set := DotSpawnOverrides.make_set("selftest", PackedStringArray([tmp]))
	var rt := DotProfileRuntime.new()
	rt.save_root = tmp
	rt.permit = func(_a: Variant, _f: String) -> bool: return true
	rt.add_set(set)
	var added := rt.handle_request("admin", DotProfileRuntime.make_request("add", "spawn", "mapx"))
	_check(added.ok, "a spawn profile for a map id is created")
	var entry := {"pos": [7.0, 0.0, 9.0], "yaw": 0.5, "team": "", "enabled": true, "weight": 2.0, "tags": ["mid"]}
	var setr := rt.handle_request("admin", DotProfileRuntime.make_request("set", "spawn", "mapx", "points.new_1", entry))
	var saved := rt.handle_request("admin", DotProfileRuntime.make_request("save", "spawn", "mapx"))
	_check(setr.ok and saved.ok, "an authored point is set and saved to the server layer")

	var fresh := DotSpawnOverrides.make_set("selftest", PackedStringArray([tmp]))
	var d := _director(DotSpawnRules.deathmatch())
	d.add_site(DotSpawnSite.point(&"base", Vector3.ZERO))
	var loaded := d.load_overrides(fresh, "mapx")
	_check(loaded.ok and int(loaded.value) == 1 and d.sites().size() == 2, "a fresh process loads the saved point onto the map's sites")
	var got := d.sites()[1]
	_check(got.id == &"new_1" and got.position == Vector3(7.0, 0.0, 9.0) and got.weight == 2.0 and got.tags == PackedStringArray(["mid"]), "the loaded point keeps its position, weight and tags")
	_check(d.load_overrides(fresh, "no_such_map").ok and d.sites().size() == 2, "a map with no overrides changes nothing")
	DirAccess.remove_absolute(tmp)
