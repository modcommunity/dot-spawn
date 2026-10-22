extends Node

## Exercises DotEntitySpawner with a fake clock: pools, caps, respawn timing, seeds, profiles.

const SECTIONS := 10
const CHECKS := 62

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_line("DotEntitySpawner self-test")
	_test_pool()
	_test_cap()
	_test_timing()
	_test_determinism()
	_test_profile()
	_test_bad_input()
	_test_disabled()
	_test_legacy_folder()
	_test_watch_and_example()
	_test_trigger_and_limits()
	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return
	if _passed + _failed != CHECKS:
		_line("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _factory(what: StringName, pos: Vector3, index: int) -> Variant:
	var e := RefCounted.new()
	e.set_meta("what", what)
	e.set_meta("pos", pos)
	e.set_meta("index", index)
	return e


func _spawner(p_seed: int = 1) -> DotEntitySpawner:
	var s := DotEntitySpawner.new(&"t", p_seed)
	s.factory = _factory
	return s


func _run(s: DotEntitySpawner, seconds: int) -> Array:
	var all: Array = []
	for i in range(seconds):
		all.append_array(s.advance(1.0))
	return all


func _test_pool() -> void:
	_section("weighted pool")
	var s := _spawner(7)
	s.add_entry(&"common", 9.0)
	s.add_entry(&"rare", 1.0)
	s.add_entry(&"never", 0.0)
	s.count = 1
	s.max_alive = 1000
	s.respawn = DotEntitySpawner.RESPAWN_TIMER
	s.interval = 1.0
	var made := _run(s, 2000)
	var tally := {}
	for e in made:
		tally[e.get_meta("what")] = int(tally.get(e.get_meta("what"), 0)) + 1
	_check(not tally.has(&"never"), "zero weight is never drawn")
	var rare_share := float(tally.get(&"rare", 0)) / float(made.size())
	_check(rare_share > 0.07 and rare_share < 0.13, "rare is near 10%% (%.3f)" % rare_share)
	_check(tally.get(&"common", 0) > tally.get(&"rare", 0), "common beats rare")

	var t := _spawner()
	t.add_entry(&"a", 1.0, 2)
	t.count = 1
	t.max_alive = 10
	t.respawn = DotEntitySpawner.RESPAWN_TIMER
	t.interval = 1.0
	var empties := [0]
	t.pool_empty.connect(func(): empties[0] += 1)
	_run(t, 10)
	_check(t.spawned_total() == 2, "stock of 2 gives two spawns")
	_check(empties[0] == 1, "pool_empty fires once when stock runs out")


func _test_cap() -> void:
	_section("max_alive")
	var s := _spawner()
	s.set_what(&"x")
	s.count = 5
	s.max_alive = 3
	_check(s.advance(0.0).size() == 3, "initial count is clamped to max_alive")
	_check(s.alive_count() == 3, "three alive")
	s.respawn = DotEntitySpawner.RESPAWN_TIMER
	s.interval = 1.0
	_run(s, 5)
	_check(s.alive_count() == 3, "the timer does not exceed max_alive")
	_check(s.spawned_total() == 3, "and spawns nothing extra")


func _test_timing() -> void:
	_section("timing on a fake clock")
	var s := _spawner()
	s.set_what(&"x")
	s.initial_delay = 5.0
	s.respawn_delay = 10.0
	s.count = 1
	s.max_alive = 1
	_check(s.advance(4.9).is_empty(), "nothing before the initial delay")
	_check(s.advance(0.2).size() == 1, "spawns after the initial delay")
	_check(s.alive_count() == 1, "one alive")
	var removed_seen := []
	s.removed.connect(func(_ent, reason): removed_seen.append(reason))
	s.notify_removed(s._alive[0])
	_check(removed_seen == [&"picked_up"], "removed signal carries the reason")
	_check(s.advance(9.0).is_empty(), "no respawn inside the delay")
	_check(s.advance(1.1).size() == 1, "respawns after the delay")

	var u := _spawner()
	u.set_what(&"x")
	u.respawn = DotEntitySpawner.RESPAWN_TIMER
	u.interval = 4.0
	u.max_alive = 5
	u.count = 0
	_check(u.advance(1.0).is_empty(), "timer mode: nothing before the interval")
	_check(u.advance(4.0).size() == 1, "timer mode: one at the interval")
	_check(u.advance(4.0).size() == 1, "timer mode: another a period later")

	var j := _spawner(3)
	j.set_what(&"x")
	j.jitter = 0.5
	j.respawn_delay = 10.0
	j.max_alive = 1
	j.advance(0.0)
	var at := 0.0
	j.notify_removed(j._alive[0])
	while j.advance(0.1).is_empty() and at < 30.0:
		at += 0.1
	_check(at >= 4.8 and at <= 15.2, "jittered delay stays within +-50%% (%.1f)" % at)

	var f := _spawner()
	f.set_what(&"x")
	f.max_alive = 1
	var n := Node.new()
	f.factory = func(_w, _p, _i): return n
	f.advance(0.0)
	n.free()
	f.respawn_delay = 2.0
	f.factory = _factory
	f.advance(0.5)
	_check(f.alive_count() == 0, "a freed entity is dropped")
	_check(f.advance(2.0).size() == 1, "and replaced after the delay")


func _test_determinism() -> void:
	_section("determinism by seed")
	var a := _sigs(_spawner_from(11).advance(0.0))
	var b := _sigs(_spawner_from(11).advance(0.0))
	var c := _sigs(_spawner_from(12).advance(0.0))
	_check(a == b, "same seed, same entities and positions")
	_check(a != c, "different seed, different run")
	var s := _spawner_from(11)
	var inside := true
	for e in s.advance(0.0):
		var d: Vector3 = e.get_meta("pos") - s.origin
		inside = inside and d.length() <= 3.001 and is_zero_approx(d.y)
	_check(inside, "radius keeps positions inside the circle on the ground plane")
	s.reset()
	_check(_sigs(s.advance(0.0)) == a, "reset restarts the stream")


func _spawner_from(p_seed: int) -> DotEntitySpawner:
	var s := _spawner(p_seed)
	s.add_entry(&"p")
	s.add_entry(&"q")
	s.radius = 3.0
	s.origin = Vector3(10, 0, 0)
	s.count = 20
	s.max_alive = 20
	return s


func _sigs(list: Array) -> String:
	var out := ""
	for e in list:
		out += "%s@%s;" % [e.get_meta("what"), e.get_meta("pos")]
	return out


func _roots() -> PackedStringArray:
	var dir := "user://entity_spawner_test"
	var base := dir.path_join("cfg/game/tg/spawner")
	DirAccess.make_dir_recursive_absolute(base)
	_write(base.path_join("crate.yml"),
		"pool:\n  - id: pistol\n    weight: 3\n  - id: shotgun\n    weight: 1\ncount: 2\nmax_alive: 4\nrespawn: on_timer\ninterval: 5.0\nphases: [live]\nseed: 9\n")
	_write(base.path_join("typo.yml"), "what: pistol\nmax_alvie: 3\n")
	_write(base.path_join("range.yml"), "what: pistol\njitter: 4.0\n")
	_write(base.path_join("empty.yml"), "count: 1\n")
	_write(base.path_join("both.yml"), "what: a\npool:\n  - id: b\n")
	_write(base.path_join("noid.yml"), "pool:\n  - weight: 2\n")
	_write(base.path_join("negw.yml"), "pool:\n  - id: a\n    weight: -1\n")
	_write(base.path_join("off.yml"), "what: a\nenabled: false\n")
	return PackedStringArray([dir.path_join("cfg")])


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)


func _profile_set() -> DotProfileSet:
	var set := DotEntitySpawner.profile_set("tg")
	set.roots = _roots()
	set.cmdline = PackedStringArray(["--"])
	return set


func _test_profile() -> void:
	_section("profile load")
	var res := DotEntitySpawner.from_profile(_profile_set(), "crate", _factory)
	_check(res.ok, "a valid profile loads")
	if not res.ok:
		print(res.error.message)
		for i in range(6):
			_check(false, "skipped")
		return
	var s: DotEntitySpawner = res.value
	_check(s.pool.size() == 2 and s.count == 2 and s.max_alive == 4, "pool, count and max_alive come from the file")
	_check(s.respawn == "on_timer" and s.interval == 5.0, "respawn mode and interval")
	_check(s.phases == PackedStringArray(["live"]), "phases")
	s.set_phase("warmup")
	_check(s.advance(10.0).is_empty(), "inactive outside its phase")
	s.set_phase("live")
	_check(s.advance(0.0).size() == 2, "active in its phase")
	_check(DotEntitySpawner.profile_schemas().has("spawner"), "profile_check can find the schema")


func _test_bad_input() -> void:
	_section("bad profiles")
	for pid in ["typo", "range", "empty", "both", "noid", "negw", "missing"]:
		var r := DotEntitySpawner.from_profile(_profile_set(), pid, _factory)
		_check(not r.ok, "'%s' is refused" % pid)
	var r2 := DotEntitySpawner.from_profile(_profile_set(), "empty", _factory)
	_check(not r2.ok and r2.error.code == DotError.CODE_INVALID, "an empty pool is CODE_INVALID")


func _test_legacy_folder() -> void:
	_section("the dashed cfg/addons/dot-spawn folder")
	DotCfgLegacy.reset()
	var base := "user://entity_spawner_test/cfg/addons/dot-spawn/spawner"
	DirAccess.make_dir_recursive_absolute(base)
	_write(base.path_join("old.yml"), "what: pistol\n")
	var r := DotEntitySpawner.from_profile(_profile_set(), "old", _factory)
	_check(r.ok, "a profile in the old dashed folder still loads")
	_check(DotCfgLegacy.warned_count() == 1, "and warns once")
	DotEntitySpawner.from_profile(_profile_set(), "old", _factory)
	_check(DotCfgLegacy.warned_count() == 1, "not twice")
	var new_dir := "user://entity_spawner_test/cfg/addons/dot_spawn/spawner"
	DirAccess.make_dir_recursive_absolute(new_dir)
	_write(new_dir.path_join("old.yml"), "what: shotgun\n")
	var r2 := DotEntitySpawner.from_profile(_profile_set(), "old", _factory)
	_check(r2.ok and r2.value.pool[0]["id"] == &"shotgun", "the new folder wins when both exist")
	_check(DotEntitySpawner.ADDON == "dot_spawn", "the profile set reads the underscored folder")
	DirAccess.remove_absolute(base.path_join("old.yml"))
	DirAccess.remove_absolute(new_dir.path_join("old.yml"))


func _test_disabled() -> void:
	_section("disabled and authority")
	var r := DotEntitySpawner.from_profile(_profile_set(), "off", _factory)
	_check(r.ok and not r.value.enabled, "enabled: false loads")
	_check(r.ok and r.value.advance(100.0).is_empty(), "a disabled spawner spawns nothing")
	var s := _spawner()
	s.set_what(&"x")
	s.is_authority = false
	_check(s.advance(10.0).is_empty(), "a non-authority does not spawn")
	s.server_only = false
	_check(s.advance(0.0).size() == 1, "unless server_only is off")
	s.despawn_all()
	_check(s.alive_count() == 0, "despawn_all empties it")


class FakeWatch:
	extends RefCounted
	var reported := 0
	var forgotten := 0

	func report(_id: Variant, _pos: Vector3, _kind: StringName, _goal: bool) -> void:
		reported += 1

	func forget(_id: Variant) -> void:
		forgotten += 1


func weapon_pickup_factory(make_pickup: Callable) -> Callable:
	return func(weapon_id: StringName, pos: Vector3, _index: int) -> Variant:
		return make_pickup.call(weapon_id, pos)


func _test_watch_and_example() -> void:
	_section("watch and the weapon example")
	var w := FakeWatch.new()
	var s := _spawner()
	s.set_what(&"x")
	s.watch = w
	s.advance(0.0)
	_check(w.reported == 1, "a spawn is reported to the watch")
	s.notify_removed(s._alive[0])
	_check(w.forgotten == 1, "a removal is forgotten by it")
	var s2 := _spawner()
	s2.factory = weapon_pickup_factory(func(wid, pos): return _factory(wid, pos, 0))
	s2.add_entry(&"pistol")
	var e := s2.advance(0.0)
	_check(e.size() == 1 and e[0].get_meta("what") == &"pistol", "the example factory receives the weapon id")
	_check("DotEntitySpawner" in s2.describe() and s2.describe_lines().size() == 2, "describe lists the pool")


func _test_trigger_and_limits() -> void:
	_section("trigger and team/class limits")
	var s := _spawner()
	s.respawn = DotEntitySpawner.RESPAWN_TRIGGER
	s.max_alive = 3
	s.count = 2
	s.set_what(&"wave")
	_check(_run(s, 10).is_empty(), "on_trigger spawns nothing by itself")
	s.trigger()
	_check(_run(s, 1).size() == 2, "a trigger spawns count entities")
	s.trigger(5)
	_check(_run(s, 1).size() == 1 and s.alive_count() == 3, "max_alive caps a trigger")
	var t := _spawner()
	t.respawn = DotEntitySpawner.RESPAWN_TIMER
	t.interval = 1.0
	t.max_alive = 10
	t.team_limit = 2
	t.add_entry(&"a", 1.0, -1, {"team": "red"})
	t.add_entry(&"b", 1.0, -1, {"team": "blue"})
	_run(t, 60)
	_check(t.alive_count() == 4, "team_limit 2 allows two per team across two teams")
	var u := _spawner()
	u.respawn = DotEntitySpawner.RESPAWN_TIMER
	u.interval = 1.0
	u.max_alive = 10
	u.add_entry(&"boss", 1.0, -1, {"max_alive": 1})
	_run(u, 20)
	_check(u.alive_count() == 1, "a per-entry max_alive holds")
	u.notify_removed(u._alive[0])
	_run(u, 5)
	_check(u.alive_count() == 1, "and frees when the entity is gone")
	var v := _spawner()
	v.respawn = DotEntitySpawner.RESPAWN_TIMER
	v.interval = 1.0
	v.max_alive = 10
	v.class_limit = 1
	v.add_entry(&"x", 1.0, -1, {"class": "tank"})
	_run(v, 10)
	_check(v.alive_count() == 1, "class_limit 1 holds")
	var res := DotEntitySpawner.from_values("p", func(k): return {"seed": 0, "what": "", "pool": [{"id": "z", "team": "red"}], "count": 1, "max_alive": 4, "interval": 1.0, "respawn_delay": 1.0, "initial_delay": 0.0, "radius": 0.0, "jitter": 0.0, "respawn": "on_trigger", "enabled": true, "server_only": true, "phases": [], "team_limit": 1, "class_limit": 0}[k], _factory)
	_check(res.ok and res.value.team_limit == 1 and res.value.pool[0]["team"] == "red", "a profile carries the limits and entry tags")


func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
