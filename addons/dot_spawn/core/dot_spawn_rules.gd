@tool
class_name DotSpawnRules
extends DotConfig

## Every policy about where things enter the world, in one layered configuration.

@export_group("Choosing")

## How a site is picked out of the ones that are allowed.
##
## [b]Deathmatch wants [code]RANDOM[/code] and nothing cleverer.[/b] A safest-first
## selector in a free-for-all sends everyone to the same quiet corner, which is a worse
## experience than the occasional bad spawn it was avoiding; and it is deterministic, so
## everyone learns the corner.
@export_enum("random", "safest", "furthest", "round_robin", "nearest_friend", "first")
var mode: int = 0

## How much distance from the nearest enemy is worth, in score per metre.
@export_range(0.0, 100.0, 0.1) var enemy_distance_weight: float = 1.0

## How much distance from the nearest team-mate is worth. Negative prefers company.
@export_range(-100.0, 100.0, 0.1) var friend_distance_weight: float = 0.0

## Score subtracted from a site an enemy can currently see.
##
## Large on purpose. Spawning in view of somebody who is already aiming is the single
## worst thing a spawn selector does, and it is worth walking a long way to avoid.
@export_range(0.0, 100000.0, 1.0) var visible_penalty: float = 500.0

## Score subtracted from a site inside [member cooldown_ticks] of its last use.
@export_range(0.0, 100000.0, 1.0) var cooldown_penalty: float = 250.0

## Score subtracted per thing already standing on a site.
@export_range(0.0, 100000.0, 1.0) var occupancy_penalty: float = 400.0

## How much a site's own priority is worth.
@export_range(0.0, 10000.0, 1.0) var priority_weight: float = 100.0

## Ticks a site scores badly for after it is used. Sites may override it.
@export_range(0, 100000, 1) var cooldown_ticks: int = 128

## Enemies closer than this make a site unusable rather than merely bad.
##
## Zero disables the hard floor. Non-zero is what a round-based mode wants: there is a
## distance at which a spawn is not a bad spawn, it is a death, and no amount of scoring
## should be able to trade it away.
@export_range(0.0, 1000.0, 0.1) var minimum_enemy_distance: float = 0.0

## Whether to fall back to the best rejected site when everything is rejected.
##
## [b]On, and it has to be.[/b] A round where every site fails its conditions is a round
## where nobody spawns, and a player looking at a black screen cannot tell that from a
## crash. Better a bad spawn, logged, than no spawn.
@export var fall_back_when_nothing_passes: bool = true

@export_group("Randomness")

## The seed a run's spawn choices derive from.
##
## [b]Combined with the tick and the spawning key, never used directly.[/b] A single
## shared generator makes a spawn depend on how many other spawns happened first, which
## means a client predicting one and a server computing it disagree the moment a packet
## is late — and the symptom is a player who appears in two places.
@export var seed_value: int = 0x5EED

## Whether to mix the key of the thing being spawned into the stream.
##
## On: two players spawning on the same tick should not get the same point.
@export var per_key_stream: bool = true

@export_group("Respawning")

## Seconds between dying and being offered a spawn. Zero is instant.
@export_range(0.0, 600.0, 0.1) var respawn_delay_sec: float = 3.0

## Whether respawns are held until a wave boundary rather than granted individually.
##
## Wave respawns are the round-based modes' answer to a steady trickle of players
## arriving one at a time into a fight that is already lost.
@export var wave_respawn: bool = false

## Seconds between waves when [member wave_respawn] is on.
@export_range(0.1, 600.0, 0.1) var wave_interval_sec: float = 10.0

## Whether anything respawns at all. Off for elimination rounds.
@export var respawn_enabled: bool = true

@export_group("Protection")

## Seconds of damage immunity after entering the world. Zero is none.
##
## The setting that stops spawn camping from being free, and the one a competitive mode
## turns off because it can be abused to win a fight by dying first.
@export_range(0.0, 60.0, 0.1) var protection_sec: float = 0.0

## Whether protection ends the moment the protected thing attacks.
##
## [b]On, always, unless there is a specific reason.[/b] Protection that survives your
## own first shot is a two-second invulnerability window in a gunfight, which is worse
## than no protection at all.
@export var protection_breaks_on_attack: bool = true

## Whether protection ends when the protected thing leaves the area it spawned in.
@export var protection_breaks_on_leaving: bool = false

## Whether a protected thing can still be damaged by the world — falling, drowning.
##
## On: a player who spawns and immediately walks into a pit should not survive it. The
## protection is from other players, not from the map.
@export var world_damage_ignores_protection: bool = true


func env_prefix() -> String:
	return "DOT_SPAWN_"


func cli_prefix() -> String:
	return "spawn-"


func validate() -> DotResult:
	if wave_respawn and wave_interval_sec <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"Wave respawns with an interval of %.2f s never come round."
			% wave_interval_sec
		)

	if protection_sec > 0.0 and mode == Mode.FURTHEST and minimum_enemy_distance <= 0.0:
		# Not an error. A furthest-first selector with protection and no floor is a
		# legitimate, if unusual, combination and refusing it would be this addon
		# deciding a game's design for it.
		DotLog.debug(
			"spawn",
			"protection with a furthest-first selector and no minimum distance",
			{"protection_sec": protection_sec}
		)

	if minimum_enemy_distance > 0.0 and not fall_back_when_nothing_passes:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"A hard minimum enemy distance of %.1f m with no fallback means a "
				+ "crowded round where nobody spawns at all, and a player looking at "
				+ "a black screen cannot tell that from a crash."
			) % minimum_enemy_distance
		)

	return DotResult.success(null)


## The selection modes, by their [member mode] value.
enum Mode {
	## Uniform over everything allowed. What a deathmatch wants.
	RANDOM = 0,
	## Highest score. Far from enemies, out of sight, not recently used.
	SAFEST = 1,
	## Furthest from the nearest enemy, and nothing else.
	FURTHEST = 2,
	## Each site in turn. Predictable on purpose, for a tutorial or a test.
	ROUND_ROBIN = 3,
	## Nearest a living team-mate. What a squad-based mode wants.
	NEAREST_FRIEND = 4,
	## The first site that passes. For a single-player level with one start.
	FIRST = 5,
}


func mode_name() -> String:
	match mode:
		Mode.RANDOM: return "random"
		Mode.SAFEST: return "safest"
		Mode.FURTHEST: return "furthest"
		Mode.ROUND_ROBIN: return "round robin"
		Mode.NEAREST_FRIEND: return "nearest friend"
		Mode.FIRST: return "first"
	return "unknown"


func respawn_delay_ticks(tick_rate: int) -> int:
	return int(round(respawn_delay_sec * float(maxi(1, tick_rate))))


func protection_ticks(tick_rate: int) -> int:
	return int(round(protection_sec * float(maxi(1, tick_rate))))


func wave_interval_ticks(tick_rate: int) -> int:
	return maxi(1, int(round(wave_interval_sec * float(maxi(1, tick_rate)))))


# --- Presets ----------------------------------------------------------------

## Everybody anywhere, three seconds later, no protection.
static func deathmatch() -> DotSpawnRules:
	var r := DotSpawnRules.new()
	r.mode = Mode.RANDOM
	r.respawn_delay_sec = 3.0
	r.protection_sec = 0.0
	r.cooldown_ticks = 128
	return r


## Team sides, safest-first, five seconds, two seconds of protection.
static func team_deathmatch() -> DotSpawnRules:
	var r := DotSpawnRules.new()
	r.mode = Mode.SAFEST
	r.respawn_delay_sec = 5.0
	r.protection_sec = 2.0
	r.protection_breaks_on_attack = true
	r.enemy_distance_weight = 2.0
	return r


## One spawn at the start of a round and no respawning at all.
static func elimination() -> DotSpawnRules:
	var r := DotSpawnRules.new()
	r.mode = Mode.SAFEST
	r.respawn_enabled = false
	r.protection_sec = 0.0
	return r


## Waves every ten seconds, protection while the gate is open.
static func objective() -> DotSpawnRules:
	var r := DotSpawnRules.new()
	r.mode = Mode.NEAREST_FRIEND
	r.wave_respawn = true
	r.wave_interval_sec = 10.0
	r.respawn_delay_sec = 2.0
	r.protection_sec = 3.0
	r.friend_distance_weight = -1.0
	return r


## One start point, used every time. A course, a tutorial, a timed run.
static func single_start() -> DotSpawnRules:
	var r := DotSpawnRules.new()
	r.mode = Mode.FIRST
	r.respawn_delay_sec = 0.0
	r.cooldown_ticks = 0
	r.cooldown_penalty = 0.0
	r.occupancy_penalty = 0.0
	return r


static func presets() -> Dictionary:
	return {
		&"deathmatch": Callable(DotSpawnRules, "deathmatch"),
		&"team_deathmatch": Callable(DotSpawnRules, "team_deathmatch"),
		&"elimination": Callable(DotSpawnRules, "elimination"),
		&"objective": Callable(DotSpawnRules, "objective"),
		&"single_start": Callable(DotSpawnRules, "single_start"),
	}


static func preset(p_id: StringName) -> DotSpawnRules:
	var table := presets()

	if not table.has(p_id):
		return null

	var fn: Callable = table[p_id]
	return fn.call() as DotSpawnRules
