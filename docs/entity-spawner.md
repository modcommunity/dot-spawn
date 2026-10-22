# DotEntitySpawner: spawn anything from a profile

`DotEntitySpawner` (`runtime/dot_entity_spawner.gd`) is the general sibling of the NPC spawners: it spawns whatever a factory `Callable` produces, keyed by an id from a weighted pool, on a timer or when the last one is taken. A weapon pickup is the first use. It is a `RefCounted` with no scene dependency: the host calls `advance(delta)` each tick, so a test drives it with a fake clock.

## Using it

```gdscript
var s := DotEntitySpawner.new(&"crate_1", 42)
s.factory = func(what: StringName, pos: Vector3, index: int): return make_thing(what, pos)
s.origin = marker.global_position
s.set_what(&"pistol")                      # or s.add_entry(&"shotgun", 1.0, stock)
s.spawned.connect(func(entity, what): ...)
# every physics tick, on the authority:
s.advance(delta)
# when a player takes one:
s.notify_removed(pickup)
```

The factory returns the entity (anything; an `Object` is also tracked for being freed) or `null` for a failed spawn, which is not counted. Signals: `spawned(entity, what)`, `removed(entity, reason)` (`picked_up`, `freed`, `despawned`) and `pool_empty` (a spawn was due and every entry had zero weight or no stock left; fires once).

## Timing

| Key | Meaning |
| --- | --- |
| `initial_delay` | seconds before the first spawns; then `count` entities appear (clamped to `max_alive`) |
| `respawn: on_pickup` | each removal schedules one replacement after `respawn_delay`; nothing else spawns |
| `respawn: on_timer` | one more every `interval` while fewer than `max_alive` are alive |
| `jitter` | each delay varies by up to this fraction either way (0 to 1) |
| `radius` | entities land at a random point in this circle on the XZ plane around `origin` |
| `max_alive` | hard cap; 0 in a profile means `count` |

Delays and positions draw from one `DotRandomStream` seeded by `seed`, so the same seed and the same calls give the same run. `reset()` restarts it.

## Gating

`enabled`, `phases` (empty means always; the host calls `set_phase("live")`), and `server_only` with `is_authority`: a client that is not the authority does nothing. While gated off the clock still runs and due respawns wait. Pool entries may carry a `stock`; at 0 they are no longer drawn.

## Profiles: kind `spawner`

`cfg/addons/dot_spawn/spawner/<id>.yml`, `cfg/game/<game>/spawner/<id>.yml`, server and user tiers as [dot-core profiles](../../dot-core/docs/profiles.md). Keys: `what` or `pool` (a list of `id`, `weight`, `stock`; not both), `count`, `max_alive`, `interval`, `respawn_delay`, `initial_delay`, `radius`, `jitter`, `respawn`, `enabled`, `phases`, `server_only`, `seed`. Unknown keys fail.

```gdscript
var set := DotEntitySpawner.profile_set("mygame")
var res := DotEntitySpawner.from_profile(set, "weapon_crate", my_factory)   # DotResult
```

An empty pool, `what` with `pool`, an entry with no id or a negative weight is `CODE_INVALID`. `profile_check` knows the kind through `--schema addons/dot_spawn/runtime/dot_entity_spawner.gd` (it exposes `profile_schemas()`).

## Watch and cull

Set `watch` to a `DotSpawnWatch`, a `DotSpawnCull` or anything with `report(id, position, kind, has_goal)` and `forget(id)`; each spawn is reported and each removal forgotten. Checked by `has_method`, so none is required.

## Weapon example

The factory is the only place that knows what a weapon id means, so the spawner never names dot-weapon:

```gdscript
s.factory = func(weapon_id: StringName, pos: Vector3, _i: int) -> Variant:
    var pickup := weapon_pickup_scene.instantiate()   # the game's own pickup
    pickup.weapon_id = weapon_id
    world.add_child(pickup)
    pickup.global_position = pos
    pickup.taken.connect(func(): s.notify_removed(pickup))
    return pickup
```

`cfg/addons/dot_spawn/spawner/weapon_crate.yml` is a weighted pool of two weapons that respawns 20 seconds after a pickup.

## Test

`examples/entity_spawner_selftest.tscn`: pool weights, `max_alive`, respawn timing on a fake clock, seed determinism, profile load, bad input, disabled and authority.
