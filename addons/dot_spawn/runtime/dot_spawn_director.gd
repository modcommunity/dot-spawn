class_name DotSpawnDirector
extends Node

## Collects the sites, filters them, scores them, and answers where something goes.
##
## [b]The node is a container for a decision that is otherwise pure.[/b] Collection
## touches the scene tree; everything after it works on [DotSpawnSite] values, which is
## why [method choose_from] is public and takes its own array — a test, a replay and a
## server all reach the same answer without a world.
##
## [codeblock]
## var spawns := DotSpawnDirector.new()
## spawns.rules = DotSpawnRules.team_deathmatch()
## spawns.enemies_fn = func(team): return positions_of_enemies_of(team)
## add_child(spawns)
## spawns.refresh()
##
## var res := spawns.choose(DotSpawnRequest.make("ada", &"blue", &"rifleman", tick))
## if res.ok:
##     var choice: DotSpawnChoice = res.value
##     player.global_transform = choice.transform
## [/codeblock]

const CHANNEL := "spawn"

## Registry name, so a game can find the director without a scene path.
const SERVICE := &"dot_spawn_director"

## A site was chosen. The game does the moving; this addon only decides.
signal chosen(key: String, choice: DotSpawnChoice)

## Nothing passed and the fallback was used. Worth surfacing: it means the map's
## conditions and the mode's rules disagree, which is a content bug.
signal fell_back(key: String, why: String, tick: int)

## Somebody's respawn timer came due.
signal respawn_due(key: String, tick: int)

@export var rules: DotSpawnRules = null

## Where to look for marker and area nodes. Empty searches from this node's scene root.
@export var sites_ref: DotNodeRef = null

## Ticks per second, for turning the rules' seconds into ticks.
@export_range(1, 1000, 1) var tick_rate: int = 60

## Whether to register in [DotRegistry] under [constant SERVICE].
@export var register_service: bool = true

## Extra rules, consulted after the built-in filtering.
var conditions: Array[DotSpawnCondition] = []

## `func(team: StringName) -> Array[Vector3]`. Where the other side is.
##
## Unset, every distance term scores zero and the selector falls back to priorities and
## cooldowns — which works, and is much worse, because it will happily put somebody in
## front of somebody else.
var enemies_fn: Callable = Callable()

## `func(team: StringName) -> Array[Vector3]`. Where your own side is.
var friends_fn: Callable = Callable()

## `func(from: Vector3, to: Vector3) -> bool`. Whether one point can see another.
##
## dot-physics' [code]DotPhysicsQuery.line_of_sight_3d[/code] is exactly this shape.
var can_see_fn: Callable = Callable()

## Protection, if the rules ask for any. Created on demand.
var protection: DotSpawnProtection = null

var _sites: Array[DotSpawnSite] = []
var _round_robin: int = 0
var _respawn_at: Dictionary = {}
var _next_wave_tick: int = -1
var _last_choice: DotSpawnChoice = null


func _ready() -> void:
	if rules == null:
		rules = DotSpawnRules.new()

	if protection == null:
		protection = DotSpawnProtection.new(rules)

	if register_service:
		DotRegistry.register(SERVICE, self)


# --- Collecting -------------------------------------------------------------

## Re-reads the sites out of the scene. Call after loading a level.
##
## [param announce_empty] exists for the same reason dot-match's does: a host that
## builds its sites in code adds them on the lines after this one, and a warning on the
## way past is a false alarm for a condition corrected microseconds later.
func refresh(announce_empty: bool = true) -> void:
	var kept: Dictionary = {}

	# Cooldown history survives a refresh. A site collected fresh every round that
	# forgot when it was last used would reset its cooldowns on any call to this, and
	# "spawn cooldowns reset when the map reloads" is correct while "spawn cooldowns
	# reset whenever anything refreshes" is a bug that only appears under load.
	for site in _sites:
		kept[site.id] = site.last_used_tick

	_sites.clear()

	var root: Node = self

	if sites_ref != null:
		root = sites_ref.resolve_or_null(self, CHANNEL)

	if root == null:
		root = get_tree().current_scene if get_tree() != null else self

	if root != null:
		_collect(root)

	for site in _sites:
		if kept.has(site.id):
			site.last_used_tick = int(kept[site.id])

	if _sites.is_empty():
		if announce_empty:
			DotLog.warn(CHANNEL, "no spawn sites found", {"root": root.name if root else "<none>"})
		else:
			DotLog.debug(CHANNEL, "no spawn sites yet")
	else:
		DotLog.debug(CHANNEL, "spawn sites", {"count": _sites.size()})


func _collect(node: Node) -> void:
	for child in node.get_children():
		# has_method rather than a type test: a game may write its own marker, and the
		# contract this addon actually needs is "can produce a site", not "is one of my
		# two node classes".
		if child.has_method("to_site"):
			var site: Variant = child.call("to_site")
			if site is DotSpawnSite:
				_sites.append(site as DotSpawnSite)

		_collect(child)


## Adds a site that is not in the scene. For a level built at runtime.
func add_site(site: DotSpawnSite) -> void:
	if site != null and not _sites.has(site):
		_sites.append(site)


func remove_site(site_id: StringName) -> int:
	var removed := 0

	for i in range(_sites.size() - 1, -1, -1):
		if _sites[i].id == site_id:
			_sites.remove_at(i)
			removed += 1

	return removed


func sites() -> Array[DotSpawnSite]:
	return _sites


func clear_sites() -> void:
	_sites.clear()


# --- Choosing ---------------------------------------------------------------

## Picks a site for a request out of the collected ones.
func choose(request: DotSpawnRequest) -> DotResult:
	return choose_from(_sites, request)


## The same decision, over an array the caller supplies. The testable half.
##
## Returns a failure only when there is genuinely nothing — no sites at all, or every
## site rejected with the fallback switched off. A bad-but-used site is a success with
## [member DotSpawnChoice.fell_back] set, because a caller that treats "we had to
## compromise" as an error will leave a player unspawned over it.
func choose_from(from: Array[DotSpawnSite], request: DotSpawnRequest) -> DotResult:
	if rules == null:
		rules = DotSpawnRules.new()

	if from.is_empty():
		return DotResult.fail(
			DotError.CODE_STATE,
			"There are no spawn sites at all.",
			"A level with no markers and nothing added in code. See refresh()."
		)

	var context := _context(request)
	var allowed: Array[DotSpawnSite] = []
	var rejected: Array[DotSpawnSite] = []
	var why := ""

	for site in from:
		if not site.admits(request.team, request.player_class):
			rejected.append(site)
			if why == "":
				why = "no site admits team '%s'" % String(request.team)
			continue

		var vetoed := ""

		for condition in conditions:
			if condition != null and condition.enabled and not condition.allows(site, context):
				vetoed = condition.reason()
				break

		if vetoed == "":
			allowed.append(site)
		else:
			rejected.append(site)
			why = vetoed

	var pool := allowed

	if pool.is_empty():
		if not rules.fall_back_when_nothing_passes:
			return DotResult.fail(
				DotError.CODE_STATE,
				"Every spawn site was rejected: %s." % (why if why != "" else "no reason given"),
				"%d sites considered." % from.size()
			)

		# The fallback, and the reason it is not optional: a round where nobody spawns
		# looks exactly like a crash from the inside of a black screen.
		pool = rejected
		DotLog.warn(CHANNEL, "spawning against the rules", {
			"key": request.key, "why": why, "sites": from.size()
		})

	var rng := _rng(request)
	var picked := _pick(pool, context, rng)

	if picked == null:
		return DotResult.fail(DotError.CODE_INTERNAL, "The selector chose nothing.")

	var choice := DotSpawnChoice.new()
	choice.site = picked
	choice.transform = picked.sample(rng)
	choice.tick = request.tick
	choice.fell_back = allowed.is_empty()
	choice.reason = why if choice.fell_back else ""
	choice.considered = from.size()
	choice.allowed = allowed.size()

	picked.last_used_tick = request.tick
	_last_choice = choice

	if choice.fell_back:
		fell_back.emit(request.key, why, request.tick)

	if rules.protection_sec > 0.0:
		if protection == null:
			protection = DotSpawnProtection.new(rules)
		choice.protected_until = protection.grant(
			request.key, request.tick, tick_rate, picked.id
		)

	chosen.emit(request.key, choice)
	return DotResult.success(choice)


## The score a site gets, exposed so a game can explain a choice to a player.
func score_of(site: DotSpawnSite, request: DotSpawnRequest) -> float:
	return _score(site, _context(request))


func last_choice() -> DotSpawnChoice:
	return _last_choice


# --- Respawning -------------------------------------------------------------

## Queues [param key] to be offered a spawn once the rules' delay has passed.
##
## Returns the tick it comes due on. Idempotent: queuing somebody who is already queued
## keeps the earlier time, because a second death report — a kill credited twice, a
## client and a server both reporting — must not push a respawn further away.
func queue_respawn(key: String, tick: int) -> int:
	if not rules.respawn_enabled:
		return -1

	if _respawn_at.has(key):
		return int(_respawn_at[key])

	var due := tick + rules.respawn_delay_ticks(tick_rate)

	if rules.wave_respawn:
		if _next_wave_tick < due:
			var interval := rules.wave_interval_ticks(tick_rate)
			var waves := int(ceil(float(due - _wave_origin(tick)) / float(interval)))
			_next_wave_tick = _wave_origin(tick) + maxi(1, waves) * interval
		due = _next_wave_tick

	_respawn_at[key] = due
	return due


func cancel_respawn(key: String) -> void:
	_respawn_at.erase(key)


func respawn_pending(key: String) -> bool:
	return _respawn_at.has(key)


## Ticks until [param key] respawns, or -1 if nothing is queued.
func respawn_in(key: String, tick: int) -> int:
	if not _respawn_at.has(key):
		return -1

	return maxi(0, int(_respawn_at[key]) - tick)


## Everything due at or before [param tick], emitted and removed.
##
## Sorted, because a dictionary's key order is not a promise and two players respawning
## in a different order on a server than on a client is a desync with no obvious cause.
func take_due(tick: int) -> PackedStringArray:
	var due := PackedStringArray()

	for key: Variant in _respawn_at.keys():
		if tick >= int(_respawn_at[key]):
			due.append(String(key))

	due.sort()

	for key in due:
		_respawn_at.erase(key)
		respawn_due.emit(key, tick)

	return due


## One tick of everything this node runs on its own: protection and respawn timers.
func advance(tick: int) -> PackedStringArray:
	if protection != null:
		protection.advance(tick)

	return take_due(tick)


func clear_respawns() -> void:
	_respawn_at.clear()
	_next_wave_tick = -1


# --- Reporting --------------------------------------------------------------

## Tells the director how many things are standing on a site.
##
## Pushed rather than polled: this addon has no way to look, and a director that
## raycasted for occupancy would be making a physics decision a game has already made
## somewhere better.
func set_occupancy(site_id: StringName, count: int) -> void:
	for site in _sites:
		if site.id == site_id:
			site.occupants = maxi(0, count)


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("dot-spawn: %d sites, %s selection" % [_sites.size(), rules.mode_name()])
	out.append("  %d respawns queued" % _respawn_at.size())

	if rules.wave_respawn:
		out.append("  waves every %.1f s, next at tick %d" % [
			rules.wave_interval_sec, _next_wave_tick
		])

	for site in _sites:
		out.append("  " + site.describe())

	for condition in conditions:
		if condition != null:
			out.append("  condition: " + condition.describe())

	if protection != null:
		out.append_array(protection.describe_lines())

	return out


func describe() -> String:
	return "DotSpawnDirector(%d sites, %s)" % [_sites.size(), rules.mode_name()]


# --- Internals --------------------------------------------------------------

func _context(request: DotSpawnRequest) -> Dictionary:
	var enemies: Array = []
	var friends: Array = []

	if enemies_fn.is_valid():
		enemies = enemies_fn.call(request.team)

	if friends_fn.is_valid():
		friends = friends_fn.call(request.team)

	return {
		"key": request.key,
		"team": request.team,
		"class": request.player_class,
		"tick": request.tick,
		"enemies": enemies,
		"friends": friends,
		"can_see": can_see_fn,
		"extra": request.extra,
	}


## One generator per request, derived from the seed, the tick and the key.
##
## [b]Never a shared member.[/b] A single stream makes a spawn depend on how many other
## spawns happened first, so a server that processed two deaths this tick and a client
## that saw one get different points — and the player materialises in two places.
##
## [b]The seed is mixed by [DotRandomStream], not by hand.[/b] This used to fold the key
## in with [code]hash(request.key)[/code], and Godot's [method String.hash] is 32-bit and
## is not promised to be stable across engine versions — so the same seed, the same tick
## and the same key could pick a different spawn point after an engine upgrade, on a
## machine that upgraded before the one it is playing against. [method
## DotRandomStream.stream] hashes the name with FNV-1a over its bytes, which is the same
## number for ever.
##
## Still returns a [RandomNumberGenerator]: the samplers a host supplies are declared as
## [code]func(rng: RandomNumberGenerator)[/code] and that is a published extension point.
## What changed is where the seed comes from, not what a caller is handed.
func _rng(request: DotSpawnRequest) -> RandomNumberGenerator:
	var stream := DotRandomStream.new(rules.seed_value, &"spawn")

	if rules.per_key_stream and not request.key.is_empty():
		stream = stream.stream(StringName(request.key))

	var rng := RandomNumberGenerator.new()
	# `at` rather than `next`: the draw must not depend on how many spawns came
	# before it, which is the same reason this function exists at all.
	rng.seed = stream.at(request.tick)
	return rng


func _pick(
	pool: Array[DotSpawnSite],
	context: Dictionary,
	rng: RandomNumberGenerator
) -> DotSpawnSite:
	if pool.is_empty():
		return null

	match rules.mode:
		DotSpawnRules.Mode.FIRST:
			return pool[0]

		DotSpawnRules.Mode.ROUND_ROBIN:
			var site := pool[_round_robin % pool.size()]
			_round_robin += 1
			return site

		DotSpawnRules.Mode.RANDOM:
			return pool[rng.randi_range(0, pool.size() - 1)]

		DotSpawnRules.Mode.FURTHEST:
			return _best(pool, func(s: DotSpawnSite) -> float:
				return _nearest_distance(s, context.get("enemies", []))
			)

		DotSpawnRules.Mode.NEAREST_FRIEND:
			return _best(pool, func(s: DotSpawnSite) -> float:
				var d := _nearest_distance(s, context.get("friends", []))
				# No friends alive is not "infinitely good"; it is no information, and
				# a selector that treated it as a maximum would pick the most isolated
				# site on the map for the first player of the round.
				return 0.0 if d >= INF else -d
			)

		_:
			return _best(pool, func(s: DotSpawnSite) -> float: return _score(s, context))


## Highest scorer, with ties broken by priority and then by id.
##
## Deterministic ties matter: two sites that score identically must resolve the same way
## on every machine, and array order out of a scene tree walk is not something to rely
## on across a client and a server that loaded the level differently.
func _best(pool: Array[DotSpawnSite], scorer: Callable) -> DotSpawnSite:
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


func _score(site: DotSpawnSite, context: Dictionary) -> float:
	var score := float(site.priority) * rules.priority_weight

	var enemies: Array = context.get("enemies", [])
	var friends: Array = context.get("friends", [])

	var enemy_d := _nearest_distance(site, enemies)
	if enemy_d < INF:
		score += enemy_d * rules.enemy_distance_weight

	var friend_d := _nearest_distance(site, friends)
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
## INF rather than zero, and every caller checks: an empty enemy list means "no
## information", and scoring it as "an enemy is standing here" would make every site
## equally terrible in the one case where the selector has a free choice.
func _nearest_distance(site: DotSpawnSite, points: Array) -> float:
	var nearest := INF

	for p: Variant in points:
		var d := site.position.distance_to(p as Vector3)
		if d < nearest:
			nearest = d

	return nearest


func _wave_origin(tick: int) -> int:
	return tick if _next_wave_tick < 0 else _next_wave_tick
