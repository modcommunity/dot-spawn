@tool
class_name DotSpawnCullRules
extends DotConfig

## Every number of the mover watch and the cull, layered config. Off by default.

const ACTIONS := "ignore,nudge,teleport,despawn,kill"

@export_group("Watch")

## Master switch. Off, the watch and the cull do nothing and cost nothing.
@export var enabled: bool = false

## Seconds between samples of one mover.
@export_range(0.05, 60.0, 0.05) var sample_sec: float = 0.5

## Most movers sampled in one advance; 0 is the share that keeps every mover on its period.
@export_range(0, 100000, 1) var max_per_tick: int = 0

## Microseconds one advance may spend before it stops and carries on next tick. 0 is no cap.
@export_range(0, 1000000, 1) var budget_usec: int = 2000

## Seconds between the navigation and reachability callables for one mover.
@export_range(0.1, 60.0, 0.1) var probe_sec: float = 2.0

## A mover with a goal that stays inside this radius (metres) for stuck_sec is stuck.
@export_range(0.05, 100.0, 0.05) var stuck_radius: float = 0.75
@export_range(0.5, 600.0, 0.1) var stuck_sec: float = 4.0

## Below this height (or non-finite) a mover fell out of the world.
@export var kill_y: float = -50.0

## Farther than this from the navigation (nav_distance_fn) for off_nav_sec is off nav.
@export_range(0.0, 1000.0, 0.1) var off_nav_distance: float = 3.0
@export_range(0.0, 600.0, 0.1) var off_nav_sec: float = 4.0

## No path from any player (reachable_fn) for unreachable_sec is unreachable.
@export_range(0.0, 600.0, 0.1) var unreachable_sec: float = 8.0

## Farther than far_distance from every player for far_sec is lost.
@export_range(0.0, 10000.0, 0.5) var far_distance: float = 30.0
@export_range(0.0, 600.0, 0.1) var far_sec: float = 20.0

@export_group("Cull")

## Per category: ignore, nudge, teleport, despawn (no kill credit or loot) or kill.
@export_enum("ignore", "nudge", "teleport", "despawn", "kill") var stuck_action: int = 3
@export_enum("ignore", "nudge", "teleport", "despawn", "kill") var off_nav_action: int = 3
@export_enum("ignore", "nudge", "teleport", "despawn", "kill") var fell_out_action: int = 3
@export_enum("ignore", "nudge", "teleport", "despawn", "kill") var unreachable_action: int = 3
@export_enum("ignore", "nudge", "teleport", "despawn", "kill") var far_action: int = 3

## Nudges a stuck mover gets before its stuck_action.
@export_range(0, 20, 1) var stuck_nudges: int = 2

## Extra seconds a verdict must have held, beyond the watch threshold, before acting.
@export_range(0.0, 600.0, 0.1) var stuck_after_sec: float = 0.0
@export_range(0.0, 600.0, 0.1) var off_nav_after_sec: float = 0.0
@export_range(0.0, 600.0, 0.1) var unreachable_after_sec: float = 0.0
@export_range(0.0, 600.0, 0.1) var far_after_sec: float = 0.0

## Seconds after a decision before the same mover is decided on again (stops flapping).
@export_range(0.0, 600.0, 0.1) var cooldown_sec: float = 2.0

## Seconds without a verdict after which a mover's nudge count starts over.
@export_range(0.0, 3600.0, 1.0) var nudge_reset_sec: float = 30.0

## Wait rather than despawn or teleport a mover a player can see (seen_fn).
@export var refuse_while_seen: bool = true

## Kinds the cull never acts on (a boss, a scripted actor).
@export var exempt_kinds: PackedStringArray = PackedStringArray()


func env_prefix() -> String:
	return "DOT_SPAWN_CULL_"


func cli_prefix() -> String:
	return "--cull-"


func validate() -> DotResult:
	if sample_sec <= 0.0 or stuck_sec <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "sample_sec and stuck_sec must be above zero.")
	return DotResult.success(null)


func action_for(category: int) -> int:
	match category:
		DotSpawnVerdict.Category.STUCK: return stuck_action
		DotSpawnVerdict.Category.OFF_NAV: return off_nav_action
		DotSpawnVerdict.Category.FELL_OUT: return fell_out_action
		DotSpawnVerdict.Category.UNREACHABLE: return unreachable_action
		DotSpawnVerdict.Category.FAR: return far_action
	return DotSpawnDecision.Action.IGNORE


func after_for(category: int) -> float:
	match category:
		DotSpawnVerdict.Category.STUCK: return stuck_after_sec
		DotSpawnVerdict.Category.OFF_NAV: return off_nav_after_sec
		DotSpawnVerdict.Category.UNREACHABLE: return unreachable_after_sec
		DotSpawnVerdict.Category.FAR: return far_after_sec
	return 0.0
