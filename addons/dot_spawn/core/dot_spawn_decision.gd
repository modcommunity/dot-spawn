class_name DotSpawnDecision
extends RefCounted

## What the cull decided for one mover; the host applies it.

enum Action { IGNORE, NUDGE, TELEPORT, DESPAWN, KILL }

var id: Variant
var action: int = Action.IGNORE
var verdict: DotSpawnVerdict
## Why an IGNORE was ignored (disabled, exempt, not yet, cooldown, seen); empty otherwise.
var reason: String = ""


static func action_name(a: int) -> String:
	match a:
		Action.IGNORE: return "ignore"
		Action.NUDGE: return "nudge"
		Action.TELEPORT: return "teleport"
		Action.DESPAWN: return "despawn"
		Action.KILL: return "kill"
	return "unknown"


func describe() -> String:
	return "%s -> %s%s" % [verdict.describe() if verdict != null else str(id), action_name(action), " (%s)" % reason if reason != "" else ""]
