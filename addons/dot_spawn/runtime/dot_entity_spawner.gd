class_name DotEntitySpawner
extends RefCounted

## Spawns anything a factory Callable can make, on a timer, from a profile; the NPC spawners' general sibling.

## An entity was made. [param what] is the id the factory was asked for.
signal spawned(entity: Variant, what: StringName)
## A spawned entity is gone ([param reason] is "picked_up", "freed" or "despawned").
signal removed(entity: Variant, reason: StringName)
## A spawn was due and no pool entry could be drawn.
signal pool_empty

const KIND := "spawner"
const ADDON := "dot_spawn"
## The folder before the underscore rename; read through [DotCfgLegacy] until its removal date.
const LEGACY_ADDON := "dot-spawn"
const RESPAWN_PICKUP := "on_pickup"
const RESPAWN_TIMER := "on_timer"

## Profile id, for describe() and logs.
var id: StringName = &""
## `func(what: StringName, position: Vector3, index: int) -> Variant`; null means the spawn failed.
var factory: Callable
## Optional `func(entity)` that frees an entity for despawn_all().
var remover: Callable
## Where the spawner stands; entities appear around it.
var origin := Vector3.ZERO
var enabled := true
## Only the authority spawns; a client with this true and `is_authority` false does nothing.
var server_only := true
var is_authority := true
## Entries `{id, weight, stock}`; `stock` -1 is unlimited.
var pool: Array = []
var count := 1
var max_alive := 1
var interval := 10.0
var respawn_delay := 10.0
var initial_delay := 0.0
## Entities land at a random point in this circle (XZ) around [member origin].
var radius := 0.0
## Fraction (0..1) a delay may vary by, either way.
var jitter := 0.0
var respawn := RESPAWN_PICKUP
## Phases it is active in; empty means always.
var phases := PackedStringArray()
## Optional DotSpawnWatch or DotSpawnCull: anything with report(id, pos, kind, has_goal) / forget(id).
var watch: Object = null
var watch_kind: StringName = &"entity"

var _rng: DotRandomStream
var _seed := 0
var _clock := 0.0
var _phase := ""
var _started := false
var _next_timer := 0.0
var _due: Array[float] = []
var _alive: Array = []
var _positions := {}
var _index := 0
var _spawn_total := 0
var _empty_reported := false


func _init(p_id: StringName = &"", p_seed: int = 0) -> void:
	id = p_id
	set_seed(p_seed)


## Restarts the random stream; the same seed and calls give the same entities and positions.
func set_seed(p_seed: int) -> void:
	_seed = p_seed
	_rng = DotRandomStream.new(p_seed, StringName("entity_spawner/%s" % id))


## Sets the single thing to spawn, replacing the pool.
func set_what(what: StringName) -> void:
	pool = [{"id": what, "weight": 1.0, "stock": -1}]


## Adds a weighted pool entry; [param stock] -1 never runs out.
func add_entry(what: StringName, weight: float = 1.0, stock: int = -1) -> void:
	pool.append({"id": what, "weight": weight, "stock": stock})


## Names the current game phase; the spawner is active only in its `phases`.
func set_phase(phase: String) -> void:
	_phase = phase


## Whether it would spawn now: enabled, authority rule met and phase allowed.
func is_active() -> bool:
	if not enabled:
		return false
	if server_only and not is_authority:
		return false
	return phases.is_empty() or phases.has(_phase)


## Entities currently alive that this spawner made.
func alive_count() -> int:
	return _alive.size()


## Total spawned since creation or reset().
func spawned_total() -> int:
	return _spawn_total


## The host says an entity was picked up (or otherwise consumed); schedules its replacement.
func notify_removed(entity: Variant, reason: StringName = &"picked_up") -> void:
	var at := _alive.find(entity)
	if at < 0:
		return
	_alive.remove_at(at)
	_forget(entity)
	if respawn == RESPAWN_PICKUP:
		_due.append(_clock + _delay(respawn_delay))
	removed.emit(entity, reason)


## Moves the clock on by [param delta] seconds and spawns what is due. Returns the entities made.
func advance(delta: float) -> Array:
	var made: Array = []
	_clock += maxf(delta, 0.0)
	if not is_active():
		return made
	_sweep()
	if not _started:
		if _clock < initial_delay:
			return made
		_started = true
		_next_timer = _clock + _delay(interval)
		for i in range(mini(count, max_alive)):
			_try_spawn(made)
	if respawn == RESPAWN_PICKUP:
		_due.sort()
		while not _due.is_empty() and _due[0] <= _clock:
			if _alive.size() >= max_alive:
				break
			_due.remove_at(0)
			_try_spawn(made)
	elif _clock >= _next_timer:
		if _alive.size() < max_alive:
			_try_spawn(made)
		_next_timer = _clock + _delay(interval)
	return made


## Removes every living entity (through [member remover] when set) and keeps the pool.
func despawn_all() -> void:
	for e in _alive.duplicate():
		_alive.erase(e)
		_forget(e)
		if remover.is_valid():
			remover.call(e)
		removed.emit(e, &"despawned")


## Back to the start: nothing alive, pool stock untouched, clock zero, stream restarted.
func reset() -> void:
	despawn_all()
	_clock = 0.0
	_started = false
	_due.clear()
	_spawn_total = 0
	_index = 0
	_empty_reported = false
	set_seed(_seed)


func describe() -> String:
	return "DotEntitySpawner %s: %s, %d/%d alive, %d spawned, %s, clock %.1f, pool [%s]" % [
		id, "active" if is_active() else "idle", _alive.size(), max_alive, _spawn_total,
		respawn, _clock, ", ".join(_pool_names())]


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray([describe()])
	for e in pool:
		out.append("  %s weight %s stock %s" % [e["id"], e["weight"], e["stock"]])
	return out


## The profile schema for [DotProfileSet]; kind `spawner`.
static func schema() -> Array:
	var f := DotProfileSet.field
	return [
		f.call("what", "string", ""),
		f.call("pool", "list", []),
		f.call("count", "int", 1, {"min": 0, "max": 1000}),
		f.call("max_alive", "int", 0, {"min": 0, "max": 1000}),
		f.call("interval", "float", 10.0, {"min": 0.0, "max": 86400.0}),
		f.call("respawn_delay", "float", 10.0, {"min": 0.0, "max": 86400.0}),
		f.call("initial_delay", "float", 0.0, {"min": 0.0, "max": 86400.0}),
		f.call("radius", "float", 0.0, {"min": 0.0, "max": 10000.0}),
		f.call("jitter", "float", 0.0, {"min": 0.0, "max": 1.0}),
		f.call("respawn", "string", RESPAWN_PICKUP, {"enum": [RESPAWN_PICKUP, RESPAWN_TIMER]}),
		f.call("enabled", "bool", true),
		f.call("phases", "list", []),
		f.call("server_only", "bool", true),
		f.call("seed", "int", 0),
	]


## For `profile_check --schema`: this addon's kinds and their fields.
static func profile_schemas() -> Dictionary:
	return {KIND: schema()}


## A profile set for kind `spawner` in [param game].
static func profile_set(game: String) -> DotProfileSet:
	return DotProfileSet.create(ADDON, game, KIND, schema())


## Builds a spawner from profile [param profile_id]; fails on a pool that cannot spawn anything.
static func from_profile(set: DotProfileSet, profile_id: String, p_factory: Callable) -> DotResult:
	var res := set.load_profile(profile_id)
	if not res.ok:
		var old := _legacy_set(set)
		if old.list_ids().has(profile_id) and not set.list_ids().has(profile_id):
			res = old.load_profile(profile_id)
	if not res.ok:
		return res
	return from_values(profile_id, res.value.get_value, p_factory)


## The same set over the pre-rename folder `cfg/addons/dot-spawn/`; warns once per file found there.
static func _legacy_set(set: DotProfileSet) -> DotProfileSet:
	var old := DotProfileSet.create(LEGACY_ADDON, set.game, KIND, schema())
	old.roots = set.roots
	old.cmdline = set.cmdline
	old.user_root = set.user_root
	old.user_tier_enabled = set.user_tier_enabled
	for root in (set.roots if not set.roots.is_empty() else DotProfileSet.default_roots()):
		var base := root.path_join("addons")
		for id in old.list_ids():
			DotCfgLegacy.find(base.path_join(LEGACY_ADDON).path_join(KIND).path_join(id + ".yml"),
				base.path_join(ADDON).path_join(KIND).path_join(id + ".yml"))
	return old


## Builds one from any getter `func(key) -> Variant` (a loaded profile's get_value, or a test's dictionary).
static func from_values(p_id: String, getter: Callable, p_factory: Callable) -> DotResult:
	var s := DotEntitySpawner.new(StringName(p_id), int(getter.call("seed")))
	s.factory = p_factory
	var what := str(getter.call("what"))
	var raw: Array = getter.call("pool")
	if what != "" and not raw.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "spawner '%s': set either what or pool, not both" % p_id)
	if what != "":
		s.set_what(StringName(what))
	for e in raw:
		if not (e is Dictionary) or str(e.get("id", "")) == "":
			return DotResult.fail(DotError.CODE_INVALID, "spawner '%s': every pool entry needs an id" % p_id)
		var w := float(e.get("weight", 1.0))
		if is_nan(w) or is_inf(w) or w < 0.0:
			return DotResult.fail(DotError.CODE_INVALID, "spawner '%s': bad weight for '%s'" % [p_id, e["id"]])
		s.add_entry(StringName(str(e["id"])), w, int(e.get("stock", -1)))
	var total := 0.0
	for e in s.pool:
		total += e["weight"]
	if s.pool.is_empty() or total <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "spawner '%s': needs what, or a pool with a positive weight" % p_id)
	s.count = int(getter.call("count"))
	s.max_alive = int(getter.call("max_alive"))
	if s.max_alive <= 0:
		s.max_alive = maxi(s.count, 1)
	s.interval = float(getter.call("interval"))
	s.respawn_delay = float(getter.call("respawn_delay"))
	s.initial_delay = float(getter.call("initial_delay"))
	s.radius = float(getter.call("radius"))
	s.jitter = float(getter.call("jitter"))
	s.respawn = str(getter.call("respawn"))
	s.enabled = bool(getter.call("enabled"))
	s.server_only = bool(getter.call("server_only"))
	s.phases = PackedStringArray(getter.call("phases"))
	return DotResult.success(s)


func _try_spawn(made: Array) -> void:
	var weights := PackedFloat32Array()
	for e in pool:
		weights.append(0.0 if e["stock"] == 0 else e["weight"])
	var at := _rng.next_weighted(weights)
	if at < 0:
		if not _empty_reported:
			_empty_reported = true
			pool_empty.emit()
		return
	var entry: Dictionary = pool[at]
	var pos := origin
	if radius > 0.0:
		var p := _rng.next_point_in_circle(radius)
		pos += Vector3(p.x, 0.0, p.y)
	if not factory.is_valid():
		return
	var entity: Variant = factory.call(entry["id"], pos, _index)
	if entity == null:
		return
	_index += 1
	_spawn_total += 1
	if entry["stock"] > 0:
		entry["stock"] -= 1
	_alive.append(entity)
	made.append(entity)
	if entity is Object:
		_positions[entity.get_instance_id()] = pos
		if watch != null and watch.has_method("report"):
			watch.report(entity.get_instance_id(), pos, watch_kind, false)
	spawned.emit(entity, entry["id"])


func _sweep() -> void:
	for e in _alive.duplicate():
		if typeof(e) == TYPE_OBJECT and not is_instance_valid(e):
			_alive.erase(e)
			if respawn == RESPAWN_PICKUP:
				_due.append(_clock + _delay(respawn_delay))
			removed.emit(null, &"freed")


func _forget(entity: Variant) -> void:
	if typeof(entity) == TYPE_OBJECT and is_instance_valid(entity):
		_positions.erase(entity.get_instance_id())
		if watch != null and watch.has_method("forget"):
			watch.forget(entity.get_instance_id())


func _delay(base: float) -> float:
	if jitter <= 0.0:
		return base
	return maxf(base * (1.0 + _rng.next_range_f(-jitter, jitter)), 0.0)


func _pool_names() -> PackedStringArray:
	var out := PackedStringArray()
	for e in pool:
		out.append(str(e["id"]))
	return out
