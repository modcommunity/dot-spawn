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

const SECTIONS := 10
const CHECKS := 162

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
