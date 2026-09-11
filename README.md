This is the **spawn** asset for TMC's **Dot** collection. It decides where anything enters the world — players, NPCs, props — and, more usefully, why that place rather than another one.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## An area is not a bigger point

A point spawn works for one thing at a time, and fails in the exact case a round begins: sixteen collision capsules at one coordinate, which the engine resolves by launching them across the map. `DotSpawnArea3D` and `DotSpawnArea2D` hold as many as they have room for, and the point inside is picked **per request** rather than per site.

An area is also the natural place for a **safe zone** — and that is a rule a damage system *asks about* rather than a rule this addon enforces:

```gdscript
if area.protects_key(victim_key, attacker_team):
    return 0.0
```

One question, one answer. dot-combat can call it; dot-spawn never calls dot-combat; a game with neither can use the same area for a shop, a lobby or a finish line.

## Install

Copy `addons/dot_spawn/` and `addons/dot_core/` into your project and enable both in *Project → Project Settings → Plugins*.

Requires Godot 4.7 or newer.

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

## Six ways to choose

| | |
| --- | --- |
| `random` | Uniform. **What deathmatch wants.** A safest-first selector in a free-for-all sends everyone to the same quiet corner, deterministically, and everyone learns it. |
| `safest` | Highest score: far from enemies, out of sight, not recently used, not occupied. |
| `furthest` | Furthest from the nearest enemy, and nothing else. |
| `round_robin` | Each in turn. Predictable on purpose, for a tutorial or a test. |
| `nearest_friend` | Beside a living team-mate. |
| `first` | The first that passes. For a course with one start. |

`DotSpawnRules` is a `DotConfig`, so all of it layers: exported defaults < JSON file < environment < command line.

## Conditions veto; weights merely argue

`DotSpawnCondition.allows()` is a veto and `bonus()` is an opinion, and keeping them apart is the point. A condition that expresses a veto as a large penalty **will still pick the forbidden site when it is the only one left** — which is how a game ends up spawning the attacking team inside the defenders' base in the one round where it matters.

Four ship: `MinimumEnemyDistance`, `OutOfSight`, `NotOccupied`, `MetaEquals`. Subclass `DotSpawnCondition` for the fifth.

## When everything fails, something still spawns

`fall_back_when_nothing_passes` defaults to on, and it has to. A round where every site fails its conditions is a round where nobody spawns, and **a player looking at a black screen cannot tell that from a crash**. The choice comes back with `fell_back` set, a reason attached, a warning in the log and a signal fired — because a map whose conditions can never be satisfied is a content bug and is otherwise completely invisible.

## The randomness is per request, not per director

One generator seeded from `(seed, tick, key)` per call, never a shared member. A single stream makes a spawn depend on how many *other* spawns happened first, so a server that processed two deaths this tick and a client that saw one get different points — and the player materialises in two places. The suite checks two directors agree over forty choices, and checks a different seed disagrees, because a test that cannot fail is not a test.

## Respawn timers, including waves

`queue_respawn`, `take_due`, `advance`. Queuing somebody twice keeps the earlier time — a kill credited twice must not push a respawn further away. Due keys come out **sorted**, because a dictionary's key order is not a promise and two machines disagreeing about it is a desync with no obvious cause.

`wave_respawn` holds everybody until the next boundary, which is the round-based modes' answer to a steady trickle of players arriving one at a time into a fight that is already lost.

## What it does not do

It does not move anything. It answers a question and emits a signal; the game does the spawning. It does not raycast — `can_see_fn` is supplied, because this addon has no opinion about which collision layers count and dot-physics already does. It does not know what health is.

## Relationship to dot-match

dot-match has its own `DotSpawnPoint` and `DotSpawnSelector`, and they stay. Those are the *match's* view: one point per player, picked by danger, sufficient for a deathmatch and dependency-free. dot-spawn is the larger one — areas, conditions, waves, protection, 2D — for a game that needs it. A game may use either; using both means picking which one the match asks.

## Licence

MIT. See [LICENSE](LICENSE).
