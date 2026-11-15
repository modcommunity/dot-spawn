Decides where players, NPCs and props enter the world, and why that place rather than another. It answers the question and emits a signal; your game does the moving.

## Install

1. Get [Godot 4.7](https://godotengine.org/download).
2. Either use [dot-bootstrap](https://github.com/gamespice-platform/bootstrap), which clones every project and links the addons, or copy `addons/dot_spawn/` and [dot-core](https://github.com/gamespice-platform/core)'s `addons/dot_core/` into your project and enable both in *Project > Project Settings > Plugins*.

## Use

```gdscript
var spawns := DotSpawnDirector.new()
spawns.rules = DotSpawnRules.team_deathmatch()
spawns.tick_rate = 64
spawns.enemies_fn = func(team): return positions_of_enemies_of(team)
spawns.can_see_fn = func(a, b): return physics.query().line_of_sight_3d(world, a, b)
add_child(spawns)
spawns.refresh()                       # collect the markers in the level

var res := spawns.choose(DotSpawnRequest.make("ada", &"blue", &"rifleman", tick))
if res.ok:
    var choice: DotSpawnChoice = res.value
    player.global_transform = choice.transform
    if choice.fell_back:
        push_warning("this map's spawn conditions can never all be satisfied")

# Once a tick: expires protection and drains respawn timers.
for key in spawns.advance(tick):
    respawn(key)
```

`can_see_fn` is supplied by you because this addon has no opinion about which collision layers count. It does not know what health is either.

## Areas

`DotSpawnArea3D` and `DotSpawnArea2D` hold as many spawns as they have room for, and pick the point inside per request. A single point cannot start a round: sixteen capsules at one coordinate get launched across the map.

An area can also be a safe zone. Your damage code asks, and this addon never enforces it:

```gdscript
if area.protects_key(victim_key, attacker_team):
    return 0.0
```

## Ways to choose

| Selector | Picks |
| --- | --- |
| `random` | Uniform. Best for deathmatch: a safest-first rule sends everyone to the same quiet corner. |
| `safest` | Highest score: far from enemies, out of sight, not recently used, not occupied. |
| `furthest` | Furthest from the nearest enemy, nothing else. |
| `round_robin` | Each in turn. Predictable, for a tutorial or a test. |
| `nearest_friend` | Beside a living team-mate. |
| `first` | The first that passes, for a course with one start. |

## Conditions

`DotSpawnCondition.allows()` is a veto and `bonus()` is a preference. Keep them apart: a veto written as a big penalty still picks the forbidden site when it is the only one left.

| Shipped condition | Vetoes |
| --- | --- |
| `MinimumEnemyDistance` | Sites too close to an enemy. |
| `OutOfSight` | Sites an enemy can see. |
| `NotOccupied` | Sites with someone on them. |
| `MetaEquals` | Sites whose metadata does not match. |

Subclass `DotSpawnCondition` for your own.

When nothing passes, something still spawns (`fall_back_when_nothing_passes`, default on), because a black screen looks like a crash. The choice comes back with `fell_back` set, a reason, a log warning and a signal, since a map whose conditions can never be met is a content bug.

## Respawn timers

`queue_respawn`, `take_due` and `advance`. Queuing somebody twice keeps the earlier time. Due keys come out sorted so two machines agree. `wave_respawn` holds everybody until the next wave boundary.

Randomness is seeded per request from `(seed, tick, key)`, so a server and a client that saw different numbers of other spawns still agree on the point.

## Settings

`DotSpawnRules` is a `DotConfig`: exported defaults, then a JSON file, then environment, then command line.

## dot-match

dot-match has its own simpler `DotSpawnPoint` and `DotSpawnSelector` (one point per player, dependency-free), which stay. Use dot-spawn when you need areas, conditions, waves, protection or 2D.

## Testing

Import the project once, then run the self-test scene in `examples/` headless with Godot.

## Status and licence

Part of the TMC **dot-\*** family of Godot addons. Written with Claude Code and maintained by `gamemann`. Every addon has headless tests, but little of this has been played by real users yet, so expect rough edges and please [open an issue](https://github.com/gamespice-platform/spawn/issues) when you hit one.

MIT licence, see [LICENSE](LICENSE). The only closed part of the [Gamespice](https://gamespice.net) platform is the web back end; you can use your own instead of Gamespice's.
