extends Node

## Exercises dot-spawn with no level, mostly no nodes, and no renderer.
##
## Which is nearly all of it, because nearly all of it is a decision. Sites are values,
## the selection is a pure function over an array of them, and the two halves that do
## touch the engine — the marker nodes and the areas — are exercised against real nodes
## in their own sections.
##
## [codeblock]
## godot --headless --path . res://examples/spawn_selftest.tscn
## [/codeblock]

const SECTIONS := 12
const CHECKS := 213

const RATE := 64

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-spawn self-test")
	_line("")

	_test_sites()
	_test_rules()
	_test_conditions()
	_test_selection()
	_test_determinism()
	_test_fallback()
	_test_respawns()
	_test_protection()
	_test_markers()
	_test_areas()
	_test_watch()
	_test_cull()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


func _director(rules: DotSpawnRules) -> DotSpawnDirector:
	var d := DotSpawnDirector.new()
	d.rules = rules
	d.tick_rate = RATE
	d.register_service = false
	add_child(d)
	return d


func _grid(count: int, team: StringName = &"") -> Array[DotSpawnSite]:
	var out: Array[DotSpawnSite] = []

	for i in range(count):
		out.append(DotSpawnSite.point(
			StringName("s%d" % i), Vector3(float(i) * 10.0, 0, 0), 0.0, team
		))

	return out


# --- Sites ------------------------------------------------------------------

func _test_sites() -> void:
	_section("a site")

	var p := DotSpawnSite.point(&"red_start", Vector3(1, 2, 3), PI * 0.5, &"red")
	_check(p.id == &"red_start", "carries a name")
	_check(not p.is_area(), "a point is not an area")
	_check(p.admits(&"red", &""), "and admits its own team")
	_check(not p.admits(&"blue", &""), "and refuses the other one")
	_check(p.admits(&"", &""), "a request with no team is admitted by anything")

	p.classes = [&"sniper"]
	_check(p.admits(&"red", &"sniper"), "a class filter admits a matching class")
	_check(not p.admits(&"red", &"medic"), "and refuses one that does not match")
	_check(p.admits(&"red", &""), "and lets a classless request through")

	p.enabled = false
	_check(
		not p.admits(&"red", &"sniper"),
		"a disabled site admits nobody — filtering, not scoring, because a scorer that "
		+ "merely penalised it would still pick it when it is the only one left"
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var at := p.sample(rng)
	_check(
		at.origin.is_equal_approx(Vector3(1, 2, 3)),
		"a point samples to exactly itself, whatever the generator says"
	)

	var a := DotSpawnSite.area(&"blue_base", Vector3.ZERO, Vector3(5, 0, 5), &"blue")
	_check(a.is_area(), "an area is an area")

	var inside := true
	for i in range(50):
		rng.seed = i
		var o := a.sample(rng).origin
		if absf(o.x) > 5.0 or absf(o.z) > 5.0 or not is_zero_approx(o.y):
			inside = false
	_check(inside, "and fifty samples all land inside it")

	var spread := {}
	for i in range(50):
		rng.seed = i
		spread[snappedf(a.sample(rng).origin.x, 0.01)] = true
	_check(
		spread.size() > 10,
		"which are actually spread out — sixteen capsules at one coordinate is what an "
		+ "area exists to avoid, and an area that always sampled its centre would be a "
		+ "point with extra steps"
	)

	var two_d := DotSpawnSite.point(&"flat", Vector3(7, 9, 0))
	two_d.is_2d = true
	_check(two_d.position_2d() == Vector2(7, 9), "a 2D site reads back as a Vector2")
	rng.seed = 3
	_check(two_d.sample_2d(rng).origin == Vector2(7, 9), "and samples to a Transform2D")

	var copy := p.duplicate_site()
	copy.id = &"changed"
	_check(p.id == &"red_start", "a copy is a copy")
	_check(copy.classes == p.classes, "with its own class list")
	_check(p.describe().contains("red_start"), "and a site describes itself")


# --- Rules ------------------------------------------------------------------

func _test_rules() -> void:
	_section("rules")

	var r := DotSpawnRules.new()
	_check(r.validate().ok, "the defaults validate")
	_check(r.mode == DotSpawnRules.Mode.RANDOM, "and pick at random")
	_check(r.respawn_delay_ticks(RATE) == 192, "three seconds at 64 Hz is 192 ticks")
	_check(r.protection_ticks(RATE) == 0, "with no protection by default")

	var dm := DotSpawnRules.deathmatch()
	_check(
		dm.mode == DotSpawnRules.Mode.RANDOM,
		"deathmatch is random and nothing cleverer — a safest-first selector in a "
		+ "free-for-all sends everyone to the same quiet corner"
	)

	var tdm := DotSpawnRules.team_deathmatch()
	_check(tdm.mode == DotSpawnRules.Mode.SAFEST, "team deathmatch prefers the safest")
	_check(tdm.protection_ticks(RATE) == 128, "with two seconds of protection")
	_check(
		tdm.protection_breaks_on_attack,
		"that ends on your own first shot, because protection that survives it is a "
		+ "two-second invulnerability in a gunfight"
	)

	var elim := DotSpawnRules.elimination()
	_check(not elim.respawn_enabled, "elimination does not respawn")

	var obj := DotSpawnRules.objective()
	_check(obj.wave_respawn, "the objective preset respawns in waves")
	_check(obj.friend_distance_weight < 0.0, "and prefers company")

	var single := DotSpawnRules.single_start()
	_check(single.mode == DotSpawnRules.Mode.FIRST, "a course uses one start, every time")
	_check(single.cooldown_ticks == 0, "with no cooldown, because it is the only one")

	_check(DotSpawnRules.presets().size() == 5, "there are five presets")
	_check(DotSpawnRules.preset(&"objective") != null, "and they resolve by name")
	_check(DotSpawnRules.preset(&"nope") == null, "an unknown one resolves to nothing")

	var bad := DotSpawnRules.new()
	bad.wave_respawn = true
	bad.wave_interval_sec = 0.0
	# An interval of zero is clamped by the export range, so set it past the setter.
	bad.set("wave_interval_sec", -1.0)
	_check(
		not bad.validate().ok or bad.wave_interval_sec > 0.0,
		"a wave interval that never comes round is refused, or clamped so it cannot be "
		+ "set at all"
	)

	var no_fallback := DotSpawnRules.new()
	no_fallback.minimum_enemy_distance = 10.0
	no_fallback.fall_back_when_nothing_passes = false
	_check(
		not no_fallback.validate().ok,
		"a hard distance floor with no fallback is refused: a crowded round where "
		+ "nobody spawns is indistinguishable from a crash to the player looking at it"
	)

	_check(r.mode_name() == "random", "a mode has a name for a log line")
	_check(r.env_prefix() == "DOT_SPAWN_", "and the config layers the family's way")


# --- Conditions -------------------------------------------------------------

func _test_conditions() -> void:
	_section("conditions")

	var site := DotSpawnSite.point(&"s", Vector3.ZERO)

	var floor_rule := DotSpawnConditions.MinimumEnemyDistance.new(8.0)
	_check(
		floor_rule.allows(site, {"enemies": []}),
		"a distance floor allows a site with nobody near it"
	)
	_check(
		not floor_rule.allows(site, {"enemies": [Vector3(3, 0, 0)]}),
		"and vetoes one with an enemy inside it — a veto rather than a penalty, "
		+ "because there is a distance at which a spawn is not bad but fatal"
	)
	_check(
		floor_rule.allows(site, {"enemies": [Vector3(30, 0, 0)]}),
		"and allows one with an enemy far away"
	)
	_check(floor_rule.reason().contains("8"), "and says why in metres")

	var sight := DotSpawnConditions.OutOfSight.new(false, 500.0)
	var seen := func(_from: Vector3, _to: Vector3) -> bool: return true
	var blind := func(_from: Vector3, _to: Vector3) -> bool: return false

	_check(
		sight.allows(site, {"enemies": [Vector3.ONE], "can_see": seen}),
		"a soft out-of-sight condition vetoes nothing"
	)
	_check(
		sight.bonus(site, {"enemies": [Vector3.ONE], "can_see": seen}) < 0.0,
		"but penalises a site somebody is looking at"
	)
	_check(
		is_zero_approx(sight.bonus(site, {"enemies": [Vector3.ONE], "can_see": blind})),
		"and leaves one nobody can see alone"
	)
	_check(
		is_zero_approx(sight.bonus(site, {"enemies": [Vector3.ONE]})),
		"with no visibility callable at all it has no opinion, rather than assuming "
		+ "the worst and penalising every site equally"
	)

	var hard_sight := DotSpawnConditions.OutOfSight.new(true)
	_check(
		not hard_sight.allows(site, {"enemies": [Vector3.ONE], "can_see": seen}),
		"a hard one vetoes instead"
	)
	_check(
		is_zero_approx(hard_sight.bonus(site, {"enemies": [Vector3.ONE], "can_see": seen})),
		"and then has no opinion about score, because it already said no"
	)

	var occupied := DotSpawnConditions.NotOccupied.new(true)
	_check(occupied.allows(site, {}), "an empty site is not occupied")
	site.occupants = 1
	_check(not occupied.allows(site, {}), "an occupied one is vetoed")

	var big := DotSpawnSite.area(&"a", Vector3.ZERO, Vector3(5, 0, 5))
	big.occupants = 3
	_check(
		occupied.allows(big, {}),
		"an area with three in it is still a choice, because holding several is the "
		+ "reason areas exist"
	)

	var meta := DotSpawnConditions.MetaEquals.new("zone", "attackers")
	var tagged := DotSpawnSite.point(&"t", Vector3.ZERO)
	tagged.meta = {"zone": "attackers"}
	_check(meta.allows(tagged, {}), "a metadata condition matches")
	tagged.meta = {"zone": "defenders"}
	_check(not meta.allows(tagged, {}), "and refuses a different value")
	tagged.meta = {}
	_check(not meta.allows(tagged, {}), "and a site with no such key at all")

	var mismatched := DotSpawnSite.point(&"m", Vector3.ZERO)
	mismatched.meta = {"zone": 7}
	_check(
		not meta.allows(mismatched, {}),
		"comparing a number against a string answers false rather than erroring, "
		+ "because DotValue.same is total where == is not"
	)

	# --- And the same question asked of the REQUEST ---------------------------
	#
	# The condition that was missing, and the one a game with more than one kind of
	# entry point needs: a timer course whose every track starts somewhere else, an
	# objective mode whose sites belong to a point, a class with its own door. Without
	# it a game picks the site itself and the director chooses nothing.
	var per := DotSpawnConditions.MetaMatchesRequest.new("track")
	var main_site := DotSpawnSite.point(&"main", Vector3.ZERO)
	main_site.meta = {"track": 0}
	var bonus_site := DotSpawnSite.point(&"bonus", Vector3.ONE)
	bonus_site.meta = {"track": 1}

	var wants_bonus := {"extra": {"track": 1}}
	_check(per.allows(bonus_site, wants_bonus), "a per-request condition matches the request")
	_check(
		not per.allows(main_site, wants_bonus),
		"and refuses the site the request did not ask for"
	)

	# The distinction that keeps an unasked question from emptying the map.
	_check(
		per.allows(main_site, {}) and per.allows(bonus_site, {}),
		"a request that carries no such field matches every site, because 'I did not "
		+ "ask' is not 'I asked for nothing'"
	)

	var untagged := DotSpawnSite.point(&"any", Vector3.ZERO)
	_check(
		per.allows(untagged, wants_bonus),
		"a site with no opinion is usable by anybody by default"
	)
	per.require_site_meta = true
	_check(
		not per.allows(untagged, wants_bonus),
		"and is refused once the director says every site must declare one"
	)

	# The site key and the request key are allowed to differ, because the level file and
	# the game code are not written by the same person.
	var renamed := DotSpawnConditions.MetaMatchesRequest.new("zone", "objective")
	var point_site := DotSpawnSite.point(&"p", Vector3.ZERO)
	point_site.meta = {"zone": &"mid"}
	_check(
		renamed.allows(point_site, {"extra": {"objective": &"mid"}}),
		"a request key that differs from the site key is matched across"
	)

	# `extra` is carried by `make`, which is what a caller actually uses.
	var carried := DotSpawnRequest.make("ada", &"blue", &"rifleman", 12, {"track": 3})
	_check(int(carried.extra.get("track", -1)) == 3, "make() carries the extra field")

	var shared := {"track": 4}
	var one := DotSpawnRequest.make("a", &"", &"", 0, shared)
	shared["track"] = 9
	_check(
		int(one.extra.get("track", -1)) == 4,
		"and duplicates it, so a caller reusing one dictionary does not rewrite a "
		+ "request it already made"
	)


# --- Selection --------------------------------------------------------------

func _test_selection() -> void:
	_section("selection")

	var rules := DotSpawnRules.new()
	rules.mode = DotSpawnRules.Mode.FIRST
	var d := _director(rules)

	var empty := DotResult.success(null)
	empty = d.choose(DotSpawnRequest.make("ada", &"", &"", 0))
	_check(
		not empty.ok and empty.code() == DotError.CODE_STATE,
		"a director with no sites says so rather than answering nothing"
	)

	var sites := _grid(5)
	var res := d.choose_from(sites, DotSpawnRequest.make("ada", &"", &"", 0))
	_check(res.ok, "with sites, it answers")
	var choice: DotSpawnChoice = res.value
	_check(choice.site.id == &"s0", "'first' picks the first")
	_check(not choice.fell_back, "and did not have to compromise")
	_check(choice.considered == 5, "reporting how many it looked at")
	_check(choice.allowed == 5, "and how many passed")

	rules.mode = DotSpawnRules.Mode.ROUND_ROBIN
	var ids := PackedStringArray()
	for i in range(7):
		var r: DotResult = d.choose_from(sites, DotSpawnRequest.make("ada", &"", &"", i))
		ids.append(String((r.value as DotSpawnChoice).site.id))
	_check(
		ids[0] == "s0" and ids[4] == "s4" and ids[5] == "s0",
		"round robin goes round: %s" % ", ".join(ids)
	)

	rules.mode = DotSpawnRules.Mode.FURTHEST
	d.enemies_fn = func(_team: StringName) -> Array: return [Vector3.ZERO]
	var far: DotResult = d.choose_from(sites, DotSpawnRequest.make("ada", &"", &"", 0))
	_check(
		(far.value as DotSpawnChoice).site.id == &"s4",
		"furthest picks the one furthest from the nearest enemy"
	)

	rules.mode = DotSpawnRules.Mode.NEAREST_FRIEND
	d.friends_fn = func(_team: StringName) -> Array: return [Vector3(30, 0, 0)]
	var near: DotResult = d.choose_from(sites, DotSpawnRequest.make("ada", &"", &"", 0))
	_check(
		(near.value as DotSpawnChoice).site.id == &"s3",
		"nearest-friend picks the one beside a team-mate"
	)

	d.friends_fn = func(_team: StringName) -> Array: return []
	var alone: DotResult = d.choose_from(sites, DotSpawnRequest.make("ada", &"", &"", 0))
	_check(
		alone.ok,
		"with nobody alive it still answers — no friends is no information, not an "
		+ "infinitely good score for the most isolated site on the map"
	)

	# Team filtering.
	var mixed: Array[DotSpawnSite] = []
	mixed.append_array(_grid(2, &"red"))
	for s in _grid(2, &"blue"):
		s.id = StringName("b" + String(s.id))
		mixed.append(s)

	rules.mode = DotSpawnRules.Mode.FIRST
	var blue: DotResult = d.choose_from(mixed, DotSpawnRequest.make("ada", &"blue", &"", 0))
	_check(
		(blue.value as DotSpawnChoice).site.team == &"blue",
		"a team request only sees its own team's sites"
	)
	_check((blue.value as DotSpawnChoice).allowed == 2, "two of the four")

	# Priority and cooldown, through the scorer.
	rules.mode = DotSpawnRules.Mode.SAFEST
	d.enemies_fn = Callable()
	var priority_sites := _grid(3)
	priority_sites[2].priority = 5
	var best: DotResult = d.choose_from(
		priority_sites, DotSpawnRequest.make("ada", &"", &"", 0)
	)
	_check(
		(best.value as DotSpawnChoice).site.id == &"s2",
		"a site's own priority wins when nothing else separates them"
	)

	# A priority of 1 is worth 100 and a cooldown costs 250, so the recent use wins.
	# Deliberately not left at 5: a preferred start that outscores its own cooldown is
	# the correct behaviour and would make this check unable to fail.
	priority_sites[2].priority = 1
	priority_sites[2].last_used_tick = 0
	var after: DotResult = d.choose_from(
		priority_sites, DotSpawnRequest.make("ada", &"", &"", 10)
	)
	_check(
		(after.value as DotSpawnChoice).site.id != &"s2",
		"and a recent use pushes it back down, when the cooldown costs more than the "
		+ "priority is worth"
	)

	var vis_sites := _grid(3)
	d.enemies_fn = func(_team: StringName) -> Array: return [Vector3(1000, 0, 0)]
	d.can_see_fn = func(_from: Vector3, to: Vector3) -> bool: return to.x < 5.0
	var unseen: DotResult = d.choose_from(vis_sites, DotSpawnRequest.make("ada", &"", &"", 0))
	_check(
		(unseen.value as DotSpawnChoice).site.id != &"s0",
		"and a site an enemy is looking at loses badly — spawning in front of somebody "
		+ "already aiming is the worst thing a selector does"
	)

	# A two-argument callable is told who is spawning: the one way a player respawned while
	# alive is not counted as their own nearest enemy.
	var asked := [""]
	d.enemies_fn = func(_team: StringName, key: String) -> Array:
		asked[0] = key
		return []
	var _keyed: DotResult = d.choose_from(vis_sites, DotSpawnRequest.make("grace", &"", &"", 0))
	_check(asked[0] == "grace", "a callable that takes the key is told who is spawning")

	_check(d.describe_lines().size() > 1, "a director describes itself")
	_check(d.score_of(vis_sites[1], DotSpawnRequest.make("ada", &"", &"", 0)) != 0.0,
		"and can explain a site's score")

	d.queue_free()


func _test_determinism() -> void:
	_section("determinism")

	var rules := DotSpawnRules.deathmatch()
	var a := _director(rules)
	var b := _director(rules)
	var sites := _grid(20)

	var same := true
	var varied := {}

	for tick in range(40):
		var ra: DotResult = a.choose_from(_grid(20), DotSpawnRequest.make("ada", &"", &"", tick))
		var rb: DotResult = b.choose_from(_grid(20), DotSpawnRequest.make("ada", &"", &"", tick))
		var ida := (ra.value as DotSpawnChoice).site.id
		var idb := (rb.value as DotSpawnChoice).site.id
		varied[ida] = true
		if ida != idb:
			same = false

	_check(
		same,
		"two directors with one seed make the same forty choices — a client predicting "
		+ "a spawn and a server computing it must not disagree"
	)
	_check(varied.size() > 5, "and the choices are actually spread over the map")

	# The negative control: a test that cannot fail is not a test.
	var other := DotSpawnRules.deathmatch()
	other.seed_value = rules.seed_value + 1
	var c := _director(other)
	var differed := false

	for tick in range(40):
		var ra: DotResult = a.choose_from(_grid(20), DotSpawnRequest.make("ada", &"", &"", tick))
		var rc: DotResult = c.choose_from(_grid(20), DotSpawnRequest.make("ada", &"", &"", tick))
		if (ra.value as DotSpawnChoice).site.id != (rc.value as DotSpawnChoice).site.id:
			differed = true

	_check(differed, "and a different seed gives different ones, so the check can fail")

	# Two players on one tick.
	var collided := 0
	for tick in range(30):
		var r1: DotResult = a.choose_from(_grid(20), DotSpawnRequest.make("ada", &"", &"", tick))
		var r2: DotResult = a.choose_from(_grid(20), DotSpawnRequest.make("bob", &"", &"", tick))
		if (r1.value as DotSpawnChoice).site.id == (r2.value as DotSpawnChoice).site.id:
			collided += 1

	_check(
		collided < 10,
		"two players spawning on one tick usually get different points (%d of 30 "
		% collided + "collided), because the key is mixed into the stream"
	)

	a.queue_free()
	b.queue_free()
	c.queue_free()
	_check(sites.size() == 20, "and the fixture was what it said it was")


func _test_fallback() -> void:
	_section("falling back")

	var rules := DotSpawnRules.new()
	rules.mode = DotSpawnRules.Mode.FIRST
	var d := _director(rules)
	d.conditions = [DotSpawnConditions.MinimumEnemyDistance.new(1000.0)]
	d.enemies_fn = func(_team: StringName) -> Array: return [Vector3.ZERO]

	var fired: Array = []
	d.fell_back.connect(func(key: String, why: String, _tick: int) -> void:
		fired.append([key, why])
	)

	var res := d.choose_from(_grid(3), DotSpawnRequest.make("ada", &"", &"", 0))
	_check(
		res.ok,
		"when every site fails, one is used anyway — a round where nobody spawns is a "
		+ "black screen the player cannot tell from a crash"
	)
	var choice: DotSpawnChoice = res.value
	_check(choice.fell_back, "and the choice says it compromised")
	_check(choice.reason != "", "with the reason attached")
	_check(choice.allowed == 0, "and nothing passed")
	_check(
		fired.size() == 1,
		"a signal fires as well, because a map whose conditions can never be satisfied "
		+ "is a content bug and is otherwise invisible"
	)

	rules.fall_back_when_nothing_passes = false
	var refused := d.choose_from(_grid(3), DotSpawnRequest.make("ada", &"", &"", 0))
	_check(
		not refused.ok,
		"a game that would rather know can turn the fallback off"
	)
	_check(refused.error.message.contains("rejected"), "and is told what happened")

	# A team with no sites at all.
	rules.fall_back_when_nothing_passes = true
	var red_only := _grid(3, &"red")
	var blue: DotResult = d.choose_from(red_only, DotSpawnRequest.make("b", &"blue", &"", 0))
	_check(
		blue.ok and (blue.value as DotSpawnChoice).fell_back,
		"and a team with no sites of its own gets one of somebody else's, loudly"
	)

	d.queue_free()


func _test_respawns() -> void:
	_section("respawn timers")

	var rules := DotSpawnRules.new()
	rules.respawn_delay_sec = 2.0
	var d := _director(rules)

	var due_keys: Array = []
	d.respawn_due.connect(func(key: String, _tick: int) -> void: due_keys.append(key))

	var at := d.queue_respawn("ada", 100)
	_check(at == 100 + 128, "a two-second delay at 64 Hz comes due 128 ticks later")
	_check(d.respawn_pending("ada"), "and is pending until then")
	_check(d.respawn_in("ada", 100) == 128, "with the remainder readable")

	var again := d.queue_respawn("ada", 200)
	_check(
		again == at,
		"queuing somebody twice keeps the earlier time — a kill credited twice must "
		+ "not push a respawn further away"
	)

	_check(d.take_due(200).is_empty(), "nothing is due early")
	var got := d.take_due(300)
	_check(got.size() == 1 and got[0] == "ada", "and it comes due on time")
	_check(due_keys.size() == 1, "with a signal")
	_check(not d.respawn_pending("ada"), "and is then forgotten")

	d.queue_respawn("zoe", 0)
	d.queue_respawn("ada", 0)
	d.queue_respawn("mel", 0)
	var order := d.take_due(1000)
	_check(
		order[0] == "ada" and order[2] == "zoe",
		"three due at once come out sorted, because a dictionary's key order is not a "
		+ "promise and two machines disagreeing about it is a desync with no cause"
	)

	d.cancel_respawn("nobody")
	d.queue_respawn("ada", 0)
	d.cancel_respawn("ada")
	_check(not d.respawn_pending("ada"), "a respawn can be cancelled")
	_check(d.respawn_in("ada", 0) == -1, "and then has no time left")

	rules.respawn_enabled = false
	_check(d.queue_respawn("ada", 0) == -1, "a mode that does not respawn queues nothing")

	# Waves.
	var wave_rules := DotSpawnRules.objective()
	var w := _director(wave_rules)
	var first := w.queue_respawn("ada", 0)
	var second := w.queue_respawn("bob", 30)
	_check(
		first == second,
		"two deaths thirty ticks apart join the same wave (%d, %d), which is the "
		% [first, second] + "answer to a steady trickle arriving into a lost fight"
	)
	var late := w.queue_respawn("mel", 2000)
	_check(late > first, "and a much later death waits for a later wave")

	d.clear_respawns()
	_check(not d.respawn_pending("mel"), "everything can be cleared at once")

	d.queue_free()
	w.queue_free()


func _test_protection() -> void:
	_section("protection")

	var rules := DotSpawnRules.new()
	rules.protection_sec = 2.0
	var p := DotSpawnProtection.new(rules)

	var ended: Array = []
	p.ended.connect(func(key: String, why: StringName, _tick: int) -> void:
		ended.append([key, String(why)])
	)

	var until := p.grant("ada", 100, RATE, &"red_start")
	_check(until == 228, "two seconds at 64 Hz protects until tick 228")
	_check(p.is_protected("ada", 200), "and they are protected inside it")
	_check(not p.is_protected("ada", 300), "and not outside it")
	_check(p.remaining("ada", 200) == 28, "with the remainder readable")
	_check(p.origin_site("ada") == &"red_start", "and the site remembered")

	_check(p.blocks("bob", "ada", 200), "another player's damage is blocked")
	_check(
		not p.blocks("ada", "ada", 200),
		"self damage is not — a rocket jump out of your own spawn is on purpose, and "
		+ "protecting it turns the window into a free movement technique"
	)
	_check(
		not p.blocks("world", "ada", 200, true),
		"and neither is the world's, so a player who walks into a pit falls into it"
	)
	_check(not p.blocks("bob", "nobody", 200), "an unprotected player is not blocked")

	_check(p.note_attack("ada", 150), "attacking ends it")
	_check(not p.is_protected("ada", 150), "immediately")
	_check(ended.size() == 1 and ended[0][1] == "attacked", "with the reason in a signal")

	rules.protection_breaks_on_attack = false
	p.grant("bob", 0, RATE)
	_check(not p.note_attack("bob", 10), "a mode that allows it says so")
	_check(p.is_protected("bob", 10), "and the protection survives")

	rules.protection_breaks_on_leaving = true
	_check(p.note_left_area("bob", 20), "leaving the area ends it when the rules say so")

	p.grant("mel", 0, RATE)
	p.advance(500)
	_check(
		not p.is_protected("mel", 500),
		"and advance expires what is over — without it the ledger only ever grows and "
		+ "a HUD badge that hides on the signal never hides"
	)
	_check(ended.back()[1] == "expired", "with 'expired' as the reason")

	p.grant("zoe", 0, RATE)
	p.revoke("zoe", 5)
	_check(not p.is_protected("zoe", 5), "and it can be taken away outright")

	rules.protection_sec = 0.0
	var none := p.grant("kit", 77, RATE)
	_check(
		none == 77 and not p.is_protected("kit", 77),
		"a zero-length grant returns the spawn tick rather than being a special case "
		+ "every caller has to branch on"
	)

	_check(p.describe_lines().size() >= 1, "and it describes itself")
	p.clear()
	_check(p.protected_keys().is_empty(), "and clears")

	# Through the director.
	var d := _director(DotSpawnRules.team_deathmatch())
	var res := d.choose_from(_grid(3), DotSpawnRequest.make("ada", &"", &"", 0))
	_check(
		(res.value as DotSpawnChoice).protected_until > 0,
		"a director grants protection as part of choosing, so no caller has to remember"
	)
	_check(d.protection.is_protected("ada", 10), "and the ledger knows")
	_check(d.advance(10000).is_empty(), "one call advances protection and respawns")
	_check(not d.protection.is_protected("ada", 10000), "and the protection is over")

	d.queue_free()


# --- Nodes ------------------------------------------------------------------

func _test_markers() -> void:
	_section("markers")

	var m := DotSpawnMarker3D.new()
	m.site_id = &"red_start"
	m.team = &"red"
	m.site_priority = 3
	m.position = Vector3(5, 0, -5)
	m.rotation = Vector3(0, PI * 0.5, 0)
	add_child(m)

	var site := m.to_site()
	_check(site.id == &"red_start", "a marker produces a site")
	_check(site.position.is_equal_approx(Vector3(5, 0, -5)), "at its own position")
	_check(is_equal_approx(site.yaw, PI * 0.5), "facing the way it faces")
	_check(site.priority == 3, "with its priority")
	_check(not site.is_2d, "and marked as 3D")

	m.position = Vector3(50, 0, 0)
	_check(
		m.to_site().position.is_equal_approx(Vector3(50, 0, 0)),
		"and recomputes every time — a marker on a moving platform that cached would "
		+ "hand out where the lift was two minutes ago"
	)

	var m2 := DotSpawnMarker2D.new()
	m2.site_id = &"flat"
	m2.position = Vector2(11, 22)
	add_child(m2)
	var site2 := m2.to_site()
	_check(site2.is_2d, "a 2D marker produces a 2D site")
	_check(site2.position_2d() == Vector2(11, 22), "at its pixel position")

	var blank := DotSpawnMarker3D.new()
	blank.site_id = &""
	add_child(blank)
	_check(
		not blank._get_configuration_warnings().is_empty(),
		"a marker with no id warns in the editor, where the mistake has no runtime "
		+ "symptom at all"
	)

	# Collection through the director, which is the only part that walks a tree.
	var holder := Node3D.new()
	add_child(holder)
	for i in range(4):
		var mk := DotSpawnMarker3D.new()
		mk.site_id = StringName("p%d" % i)
		mk.position = Vector3(float(i), 0, 0)
		holder.add_child(mk)

	var d := _director(DotSpawnRules.new())
	d.sites_ref = DotNodeRef.of_path(holder.get_path())
	d.refresh(false)
	_check(d.sites().size() == 4, "a director collects the markers under its root")

	var code_site := DotSpawnSite.point(&"runtime", Vector3.ONE)
	d.add_site(code_site)
	_check(d.sites().size() == 5, "and takes sites built in code")
	_check(d.remove_site(&"runtime") == 1, "which can be removed again")

	# The history that must survive a refresh.
	d.sites()[0].last_used_tick = 500
	d.refresh(false)
	_check(
		d.sites()[0].last_used_tick == 500,
		"a refresh keeps each site's cooldown history — resetting it on any refresh is "
		+ "a bug that only appears under load"
	)

	d.clear_sites()
	_check(d.sites().is_empty(), "and everything can be cleared")

	m.queue_free()
	m2.queue_free()
	blank.queue_free()
	holder.queue_free()
	d.queue_free()


func _test_areas() -> void:
	_section("areas")

	var area := DotSpawnArea3D.new()
	area.site_id = &"red_base"
	area.team = &"red"
	area.safe_zone = true
	area.fallback_extents = Vector3(4, 0, 4)
	add_child(area)

	var site := area.to_site()
	_check(site.is_area(), "an area produces an area site")
	_check(site.extents.is_equal_approx(Vector3(4, 0, 4)), "with the fallback extents")
	_check(site.protects, "marked as protecting")

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 2, 10)
	shape.shape = box
	area.add_child(shape)
	_check(
		area.measured_extents().is_equal_approx(Vector3(5, 1, 5)),
		"and a box shape is measured as half its size — the other reading doubles the "
		+ "area silently and puts half the spawns outside the volume that was drawn"
	)

	_check(not area.protects_key("ada"), "nobody is protected before entering")
	area.note_entered("ada", &"red")
	_check(area.contains_key("ada"), "somebody can be recorded as inside")
	_check(area.occupant_count() == 1, "and counted")
	_check(area.protects_key("ada"), "and is then protected")
	_check(
		not area.protects_key("ada", &"", true),
		"but not from the world, because a safe zone is protection from other players "
		+ "and a player who walks into a pit inside one should fall into it"
	)
	_check(
		not area.protects_key("ada", &"red"),
		"and not from their own side"
	)

	area.note_entered("bob", &"blue")
	_check(
		not area.protects_key("bob"),
		"an attacker standing in the defenders' spawn is killable there, or the area "
		+ "becomes somewhere to stand and shoot from"
	)

	_check(area.to_site().occupants == 2, "the site carries the occupancy")
	area.note_left("ada")
	_check(not area.contains_key("ada"), "leaving is recorded")
	_check(not area.protects_key("ada"), "and the protection goes with it")

	area.safe_zone = false
	area.note_entered("mel", &"red")
	_check(
		not area.protects_key("mel"),
		"an area that is not a safe zone protects nobody, so a damage system can ask "
		+ "unconditionally"
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placed := area.sample(rng)
	_check(
		absf(placed.origin.x - area.global_position.x) <= 5.01,
		"and it places things inside itself"
	)

	area.sample_fn = func(_r: RandomNumberGenerator) -> Transform3D:
		return Transform3D(Basis.IDENTITY, Vector3(99, 99, 99))
	_check(
		area.sample(rng).origin.is_equal_approx(Vector3(99, 99, 99)),
		"a game can replace the placement entirely, which is the customisation hook a "
		+ "ring, a grid or a navmesh snap needs"
	)

	var flat := DotSpawnArea2D.new()
	flat.site_id = &"lobby"
	flat.fallback_extents = Vector2(32, 32)
	add_child(flat)
	_check(flat.to_site().is_2d, "there is a 2D area too")
	_check(flat.to_site().extents.is_equal_approx(Vector3(32, 32, 0)), "with 2D extents")
	flat.note_entered("ada")
	_check(flat.occupant_keys().size() == 1, "which tracks occupants the same way")
	flat.clear_occupants()
	_check(flat.occupant_count() == 0, "and clears them")

	_check(area.describe_lines().size() >= 1, "an area describes itself")
	var unshaped := DotSpawnArea3D.new()
	_check(
		not unshaped._get_configuration_warnings().is_empty(),
		"and warns in the editor when it has no box to measure"
	)
	unshaped.free()

	# Freed rather than queued: the suite quits on the next line and a deferred free
	# never runs, which shows up as "RID allocations were leaked at exit" in a stderr
	# this family's own rules say to read.
	area.free()
	flat.free()


# --- Watch and cull ---------------------------------------------------------

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

# --- Harness ---------------------------------------------------------------

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
