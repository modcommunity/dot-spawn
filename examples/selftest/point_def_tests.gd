extends "res://examples/selftest/scatter_tests.gd"

## Authored spawn point definitions: round trip, one veto or score case per setting.


func _def(id: String, pos: Vector3 = Vector3.ZERO) -> DotSpawnPointDef:
	var p := DotSpawnPointDef.new()
	p.id = StringName(id)
	p.position = pos
	return p


func _allowed(p: DotSpawnPointDef, cond: DotSpawnCondition, ctx: Dictionary = {}) -> bool:
	return cond.allows(p.to_site(), ctx)


func _test_point_defs() -> void:
	_section("Point defs: every setting round-trips and is enforced")

	var full := _def("alpha", Vector3(1.0, 2.0, 3.0))
	full.kind = DotSpawnPointDef.KIND_NPC
	full.enabled = false
	full.yaw = 1.25
	full.radius = 4.0
	full.team = &"red"
	full.classes = [&"medic"]
	full.group = &"wave_a"
	full.weight = 3.0
	full.cooldown = 2.5
	full.max_alive = 2
	full.phases = [&"wave_2"]
	full.sight = DotSpawnPointDef.SIGHT_HIDDEN
	full.min_player_distance = 5.0
	full.max_player_distance = 30.0
	full.source = DotSpawnPointDef.SOURCE_MAP
	full.meta = {"room": "b"}

	var set := DotSpawnPointSet.new()
	set.add(full)
	set.add(_def("beta", Vector3(9.0, 0.0, 0.0)))
	var json := JSON.stringify(set.to_dict())
	var back := DotSpawnPointSet.from_dict(JSON.parse_string(json))
	_check(back.ok and back.value.points.size() == 2, "a set survives JSON")
	_check(back.ok and JSON.stringify(back.value.to_dict()) == json, "and comes back identical, every setting included")
	_check(not DotSpawnPointSet.from_dict({"version": 99, "points": []}).ok, "a newer version is refused")
	_check(DotSpawnPointSet.from_dict({"points": [{"id": "x", "kind": "bogus"}]}).error.code == DotError.CODE_INVALID, "an unknown kind is refused")
	_check(DotSpawnPointSet.from_dict({"points": [{"id": "x"}, {"id": "x"}]}).error.code == DotError.CODE_CONFLICT, "a duplicate id is refused")
	_check(DotSpawnPointSet.from_dict({"version": 1}).ok, "an older file with missing keys loads with defaults")

	var site := full.to_site(64)
	_check(
		site.id == &"alpha" and site.position == Vector3(1.0, 2.0, 3.0) and site.team == &"red" and not site.enabled
		and site.weight == 3.0 and site.source == &"map" and site.is_area() and site.cooldown_ticks == 160 and site.classes == [&"medic"],
		"to_site carries position, team, area, weight, cooldown and classes"
	)
	_check(site.meta["room"] == "b" and site.meta[DotSpawnPointDef.META_GROUP] == "wave_a", "and keeps game meta beside the group")
	_check(not site.admits(&"red", &""), "a disabled point admits nobody")
	_check(_def("z").to_site().cooldown_ticks == -1, "no cooldown set inherits the rules' default")
	_check(DotSpawnPointDef.schema().size() == full.to_dict().size(), "the editor schema lists every setting")

	var p := _def("p")
	p.max_alive = 2
	var alive := {"alive_by_site": {&"p": 2}}
	_check(not _allowed(p, DotSpawnConditions.MaxAlive.new(), {"extra": alive}), "MaxAlive vetoes a point at its cap")
	_check(_allowed(p, DotSpawnConditions.MaxAlive.new(), {"extra": {"alive_by_site": {&"p": 1}}}), "and allows one below it")
	p.max_alive = 0
	_check(_allowed(p, DotSpawnConditions.MaxAlive.new(), {"extra": alive}), "zero is unlimited")

	p.phases = [&"wave_2"]
	var phase := DotSpawnConditions.PhaseIs.new()
	_check(_allowed(p, phase, {"extra": {"phase": "wave_2"}}), "PhaseIs allows a live phase")
	_check(not _allowed(p, phase, {"extra": {"phase": "wave_1"}}), "and vetoes another")
	_check(_allowed(p, phase, {"extra": {}}), "a request with no phase matches every point")

	p.kind = DotSpawnPointDef.KIND_PLAYER
	var kind := DotSpawnConditions.KindIs.new()
	_check(not _allowed(p, kind, {"extra": {"kind": "npc"}}) and _allowed(p, kind, {"extra": {"kind": "player"}}), "KindIs separates player and npc points")
	p.kind = DotSpawnPointDef.KIND_BOTH
	_check(_allowed(p, kind, {"extra": {"kind": "npc"}}), "a both point serves either")

	var band := DotSpawnConditions.DistanceBand.new()
	p.min_player_distance = 5.0
	p.max_player_distance = 20.0
	_check(not _allowed(p, band, {"enemies": [Vector3(2, 0, 0)]}), "DistanceBand vetoes a player too close")
	_check(not _allowed(p, band, {"friends": [Vector3(40, 0, 0)]}), "and one too far, friends counted")
	_check(_allowed(p, band, {"enemies": [Vector3(10, 0, 0)]}) and _allowed(p, band, {}), "inside the band, or with nobody to measure, passes")

	var sight := DotSpawnConditions.SightRule.new()
	var seen := {"enemies": [Vector3(10, 0, 0)], "can_see": func(_a: Vector3, _b: Vector3) -> bool: return true}
	var unseen := {"enemies": [Vector3(10, 0, 0)], "can_see": func(_a: Vector3, _b: Vector3) -> bool: return false}
	p.sight = DotSpawnPointDef.SIGHT_HIDDEN
	_check(not _allowed(p, sight, seen) and _allowed(p, sight, unseen), "hidden_from_players vetoes a watched point")
	p.sight = DotSpawnPointDef.SIGHT_VISIBLE
	_check(_allowed(p, sight, seen) and not _allowed(p, sight, unseen), "visible_to_players vetoes an unwatched one")
	p.sight = DotSpawnPointDef.SIGHT_ANY
	_check(_allowed(p, sight, seen) and _allowed(p, sight, {}), "any has no opinion")

	var w := DotSpawnConditions.WeightBonus.new(100.0)
	var heavy := _def("h")
	heavy.weight = 3.0
	var none := _def("n")
	none.weight = 0.0
	_check(w.bonus(heavy.to_site(), {}) == 200.0 and w.bonus(_def("o").to_site(), {}) == 0.0, "WeightBonus scores weight above one")
	_check(not _allowed(none, w), "and a zero weight is a veto")

	var d := _director(DotSpawnRules.deathmatch())
	d.conditions = [DotSpawnConditions.MaxAlive.new(), DotSpawnConditions.WeightBonus.new()]
	var low := _def("low", Vector3(0, 0, 0))
	var high := _def("high", Vector3(50, 0, 0))
	high.weight = 4.0
	d.add_site(low.to_site())
	d.add_site(high.to_site())
	var res := d.choose(DotSpawnRequest.make("ada", &"", &"", 0))
	_check(res.ok and (res.value as DotSpawnChoice).site.id == &"high", "through the director a heavier point wins")
	high.max_alive = 1
	d.clear_sites()
	d.add_site(low.to_site())
	d.add_site(high.to_site())
	res = d.choose(DotSpawnRequest.make("ada", &"", &"", 0, {"alive_by_site": {&"high": 1}}))
	_check(res.ok and (res.value as DotSpawnChoice).site.id == &"low", "and a full point is skipped")
	d.queue_free()

	var sites: Array[DotSpawnSite] = [DotSpawnSite.point(&"m1", Vector3.ZERO), DotSpawnSite.point(&"m2", Vector3(5, 0, 0))]
	var ov := DotSpawnPointSet.new()
	var m1 := _def("m1", Vector3(7, 0, 0))
	m1.enabled = false
	ov.add(m1)
	ov.add(_def("extra", Vector3(1, 1, 1)))
	var before := sites[0]
	var n := ov.apply_to(sites)
	_check(n == 2 and sites.size() == 3 and sites[0].id == &"m1" and not sites[0].enabled and sites[0].position.x == 7.0, "map points are overridden by id and extras added")
	_check(before.enabled and before.position == Vector3.ZERO and sites[1].id == &"m2", "the map's own site object is never edited, and untouched points stay")
	var clean: Array[DotSpawnSite] = [DotSpawnSite.point(&"m1", Vector3.ZERO)]
	_check(DotSpawnPointSet.new().apply_to(clean) == 0 and clean[0].enabled, "an empty set gives back what the map shipped")
