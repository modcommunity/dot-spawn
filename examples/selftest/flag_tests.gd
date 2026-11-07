extends "res://examples/selftest/point_def_tests.gd"

## Flag spawns: the `flag` kind, authored overrides, nobody spawning on a stand, and the cluster fallback.


func _site(id: String, pos: Vector3, team: String = "", kind: String = "") -> DotSpawnSite:
	var s := DotSpawnSite.point(StringName(id), pos, 0.0, StringName(team))

	if kind != "":
		s.meta[DotSpawnPointDef.META_KIND] = kind

	return s


func _test_flag_spawns() -> void:
	_section("Flag spawns: kind, overrides, vetoes and the fallback")

	var d := _def("f1", Vector3(1, 0, 2))
	d.kind = DotSpawnPointDef.KIND_FLAG
	_check(d.problem() != "", "a flag spawn without a team is refused")
	d.team = &"3"
	_check(d.problem() == "", "a flag spawn for team 3 is fine")
	var back := DotSpawnPointDef.from_dict(JSON.parse_string(JSON.stringify(d.to_dict())))
	_check(back.kind == DotSpawnPointDef.KIND_FLAG and back.team == &"3", "kind and team round-trip")

	var sites: Array[DotSpawnSite] = [_site("m1", Vector3.ZERO, "1")]
	var applied := DotSpawnOverrides.apply(sites, {
		"a": {"pos": [10, 0, 0], "team": "1", "kind": "flag"},
		"b": {"pos": [-10, 0, 0], "team": "2", "kind": "flag"},
		"c": {"pos": [0, 0, 30], "team": "3", "kind": "flag"},
	})
	_check(applied == 3 and sites.size() == 4, "authored flag entries are added")
	_check(DotSpawnFlags.flag_sites(sites).size() == 3 and DotSpawnFlags.player_sites(sites).size() == 1, "flag stands and player spawns separate")
	var by := DotSpawnFlags.flag_by_team(sites)
	_check(by.size() == 3 and by[3].position == Vector3(0, 0, 30), "one stand per team, three teams")
	var entry := DotSpawnOverrides.entry_of(sites[1])
	_check(entry.get("kind") == "flag" and not DotSpawnOverrides.entry_of(sites[0]).has("kind"), "the kind is written only when it is not the default")

	var cond := DotSpawnConditions.KindIs.new()
	_check(not cond.allows(sites[1], {}), "a flag stand is never a player spawn, even with no kind asked")
	_check(not cond.allows(sites[1], {"extra": {"kind": "player"}}) and cond.allows(sites[1], {"extra": {"kind": "flag"}}), "only a flag request fits it")
	_check(cond.allows(sites[0], {}) and cond.allows(sites[0], {"extra": {"kind": "player"}}), "an ordinary point still fits a player")

	var dir := _director(DotSpawnRules.deathmatch())
	dir.conditions = [DotSpawnConditions.KindIs.new()]
	for s in sites:
		dir.add_site(s)
	var ok := true
	for i in 20:
		var res := dir.choose(DotSpawnRequest.make("p%d" % i, &"", &"", i * 100, {"kind": "player"}))
		ok = ok and res.ok and not DotSpawnFlags.is_flag((res.value as DotSpawnChoice).site)
	_check(ok, "the director never spawns a player on a flag stand")
	dir.queue_free()

	var tagged: Array[DotSpawnSite] = [
		_site("r1", Vector3(-40, 0, 0), "1"), _site("r2", Vector3(-44, 0, 3), "1"),
		_site("b1", Vector3(40, 0, 0), "2"), _site("b2", Vector3(44, 0, -3), "2"),
	]
	var bases := DotSpawnFlags.bases(tagged, 2)
	_check(bases.size() == 2 and bases[1].position.x < 0.0 and bases[2].position.x > 0.0, "a map with team spawns and no flags puts each team's base in its own spawns")

	var plain: Array[DotSpawnSite] = []
	for i in 8:
		plain.append(_site("d%d" % i, Vector3(-50 + i, 0, i % 3)))
		plain.append(_site("e%d" % i, Vector3(50 - i, 0, i % 3)))
	var two := DotSpawnFlags.bases(plain, 2)
	_check(two.size() == 2 and absf(two[1].position.x - two[2].position.x) > 80.0, "untagged spawns split into opposite clusters")
	var three_pool: Array[DotSpawnSite] = plain.duplicate()
	for i in 8:
		three_pool.append(_site("f%d" % i, Vector3(i, 0, 70 + i % 3)))
	var three := DotSpawnFlags.bases(three_pool, 3)
	var spread := three.size() == 3
	if spread:
		spread = three[1].position.distance_to(three[2].position) > 60.0 and three[1].position.distance_to(three[3].position) > 40.0 and three[2].position.distance_to(three[3].position) > 40.0
	_check(spread, "three teams get three well-separated clusters")
	var mixed := DotSpawnFlags.bases(sites, 3)
	_check(mixed.size() == 3 and mixed[1].position == Vector3(10, 0, 0), "an authored stand wins over the fallback for its team")
	_check(DotSpawnFlags.bases([] as Array[DotSpawnSite], 2).is_empty(), "no spawns at all gives no bases")
