class_name DotSpawnCull
extends RefCounted

## Turns watch verdicts into one decision per mover; the host moves, kills or despawns.

const CHANNEL := "spawn"

var rules: DotSpawnCullRules = DotSpawnCullRules.new()
## (position: Vector3, id) -> bool, whether a player can see it. Unset means never seen.
var seen_fn: Callable = Callable()
## Optional appliers for apply(): each takes (id, verdict).
var nudge_fn: Callable = Callable()
var teleport_fn: Callable = Callable()
var despawn_fn: Callable = Callable()
var kill_fn: Callable = Callable()

var counts: Dictionary = {}
var by_category: Dictionary = {}

var _state: Dictionary = {}


func _init(p_rules: DotSpawnCullRules = null) -> void:
	if p_rules != null:
		rules = p_rules


## One decision for one verdict (IGNORE with a reason when nothing is due).
func decide(v: DotSpawnVerdict) -> DotSpawnDecision:
	var d := DotSpawnDecision.new()
	d.id = v.id
	d.verdict = v

	if not rules.enabled:
		d.reason = "disabled"
		return d

	if rules.exempt_kinds.has(String(v.kind)):
		d.reason = "exempt"
		return d

	var action := rules.action_for(v.category)

	if action == DotSpawnDecision.Action.IGNORE:
		d.reason = "ignored by rule"
		return d

	if v.seconds < rules.after_for(v.category):
		d.reason = "not yet"
		return d

	var st: Dictionary = _state.get(v.id, {"last": -1e9, "nudges": 0})

	if v.time - float(st["last"]) < rules.cooldown_sec:
		d.reason = "cooldown"
		return d

	if v.category != DotSpawnVerdict.Category.FELL_OUT and rules.refuse_while_seen \
			and (action == DotSpawnDecision.Action.DESPAWN or action == DotSpawnDecision.Action.TELEPORT) \
			and seen_fn.is_valid() and bool(seen_fn.call(v.position, v.id)):
		d.reason = "seen"
		return d

	if v.time - float(st["last"]) > rules.nudge_reset_sec:
		st["nudges"] = 0

	if v.category == DotSpawnVerdict.Category.STUCK and int(st["nudges"]) < rules.stuck_nudges:
		action = DotSpawnDecision.Action.NUDGE
		st["nudges"] = int(st["nudges"]) + 1

	st["last"] = v.time
	_state[v.id] = st
	d.action = action
	counts[action] = int(counts.get(action, 0)) + 1
	by_category[v.category] = int(by_category.get(v.category, 0)) + 1
	DotLog.debug(CHANNEL, "cull decision", {"mover": str(v.id), "verdict": DotSpawnVerdict.category_name(v.category),
		"action": DotSpawnDecision.action_name(action), "at": str(v.position.snappedf(0.1))})
	return d


## Decisions for a batch of verdicts: at most one per mover, its worst verdict, IGNOREs left out.
func process(verdicts: Array[DotSpawnVerdict]) -> Array[DotSpawnDecision]:
	var worst: Dictionary = {}

	for v in verdicts:
		var held: DotSpawnVerdict = worst.get(v.id)

		if held == null or v.category < held.category:
			worst[v.id] = v

	var out: Array[DotSpawnDecision] = []

	for id in worst:
		var d := decide(worst[id])

		if d.action != DotSpawnDecision.Action.IGNORE:
			out.append(d)

	return out


## Hand decisions to the applier callables; returns how many were applied.
func apply(decisions: Array[DotSpawnDecision]) -> int:
	var n := 0

	for d in decisions:
		var fn: Callable
		match d.action:
			DotSpawnDecision.Action.NUDGE: fn = nudge_fn
			DotSpawnDecision.Action.TELEPORT: fn = teleport_fn
			DotSpawnDecision.Action.DESPAWN: fn = despawn_fn
			DotSpawnDecision.Action.KILL: fn = kill_fn

		if fn.is_valid():
			fn.call(d.id, d.verdict)
			n += 1

		if d.action == DotSpawnDecision.Action.DESPAWN or d.action == DotSpawnDecision.Action.KILL:
			forget(d.id)

	return n


## Drop a mover's nudge and cooldown state once it has left the world.
func forget(id: Variant) -> void:
	_state.erase(id)


func describe() -> String:
	var parts: PackedStringArray = []

	for a in counts:
		parts.append("%s %d" % [DotSpawnDecision.action_name(a), counts[a]])

	return "DotSpawnCull(%s, %d tracked%s)" % ["on" if rules.enabled else "off", _state.size(), ", " + ", ".join(parts) if not parts.is_empty() else ""]


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray([describe()])

	for c in by_category:
		lines.append("  %s: %d" % [DotSpawnVerdict.category_name(c), by_category[c]])

	return lines
