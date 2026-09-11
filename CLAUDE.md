# dot-spawn

Where anything enters the world, and why that place.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first — no autoloads, `DotNodeRef` instead of scene paths, `DotResult` for anything fallible, `Dot`-prefixed class names, layered configuration, `describe()` on anything stateful. This file is only what is specific to spawning.

## The one idea

**Everything that decides anything works on `DotSpawnSite` values, and nothing on a scene node.**

A `DotSpawnMarker3D` produces one, a `DotSpawnArea2D` produces one, a level generator produces one out of nothing. From there the filtering, the scoring and the picking are pure functions over an array, which is why `choose_from` is public and takes its own array: a test, a replay and a server all reach the same answer with no world at all. The suite spawns 160-odd times and loads no level.

The one place the tree is touched is `DotSpawnDirector.refresh`, and it collects by `has_method("to_site")` rather than by type — because the contract this addon needs is "can produce a site", not "is one of my four node classes", and a game writing its own marker should not have to subclass one.

## Layout

```
addons/dot_spawn/
  core/
    dot_spawn_site.gd        one candidate place, as a value
    dot_spawn_request.gd     who is spawning, on which side, as what, when
    dot_spawn_choice.gd      the answer, and whether the rules were satisfied
    dot_spawn_rules.gd       every policy, as a layered DotConfig
    dot_spawn_condition.gd   the extension point: a veto and an opinion
    dot_spawn_conditions.gd  the four every project writes
    dot_spawn_protection.gd  who is briefly un-killable, as a ledger
  nodes/
    dot_spawn_marker_3d.gd   a point in a 3D level
    dot_spawn_marker_2d.gd   a point in a 2D level
    dot_spawn_area_3d.gd     a volume, and optionally a safe zone
    dot_spawn_area_2d.gd     the same in 2D
  runtime/
    dot_spawn_director.gd    collects, filters, scores, picks, times respawns
```

## Vetoes and opinions are different things

`DotSpawnCondition` has two methods on purpose. `allows()` removes a site from the pool; `bonus()` moves its score. A condition that expresses a veto as a large penalty **will still pick the forbidden site when it is the only one left**, and the round where that happens is the round where it matters.

`MinimumEnemyDistance` is the shipped example: there is a distance at which a spawn is not a bad spawn but a death, and no amount of scoring elsewhere should be able to buy it back.

`OutOfSight` deliberately has **no opinion** when no `can_see` callable is supplied, rather than assuming the worst. A condition that penalised every site equally would leave the selector with the same ordering it had and a score that looks like it did something.

## The fallback is not optional

When every site fails, one is used anyway, loudly. A round where nobody spawns is a black screen, and a black screen is indistinguishable from a crash from the player's side. The compromise is reported three ways — `DotSpawnChoice.fell_back`, a warning, and the `fell_back` signal — because a map whose conditions can never all be satisfied is a content bug with no other symptom.

`fall_back_when_nothing_passes` can be turned off by a game that would rather know, and `DotSpawnRules.validate()` refuses the one combination where that is certainly wrong: a hard distance floor with no fallback.

## One generator per request

`_rng` derives from `(seed_value, tick, key)` and is never a member. A shared stream makes a spawn depend on how many other spawns happened first, so a server that processed two deaths this tick and a client that saw one get different points, and the player materialises in two places.

The suite checks two directors agree over forty choices **and** that a different seed disagrees. The second half is the negative control; the same discipline as `dot-player-controller`'s replay-determinism test.

## Three traps already paid for here

**`site_priority`, not `priority`.** `Area2D` and `Area3D` already have a `priority` — the order overlapping areas are processed in — and GDScript refuses the collision. The markers use the same name so the four nodes read alike.

**`measured_extents` halves the box.** `BoxShape3D.size` is a full size and `DotSpawnSite.extents` are half-extents. The other reading doubles the area silently and puts half the spawns outside the volume somebody drew.

**`refresh()` keeps each site's `last_used_tick`.** A director that collected fresh sites every time would reset every cooldown on any call to it, and "spawn cooldowns reset when the map reloads" is correct while "spawn cooldowns reset whenever anything refreshes" is a bug that only appears under load.

## Protection is a ledger, not a behaviour

`DotSpawnProtection` grants, expires and revokes. It never touches health, never subscribes to a damage signal and never knows what a weapon is. `blocks(attacker, victim, tick, world_damage)` is the whole interface a damage system needs, and it answers about the *pair*: self damage is never blocked, because a rocket jump out of your own spawn is on purpose and protecting it turns a two-second window into a free movement technique.

`advance()` is necessary even though `is_protected` already compares against the tick. Without it the dictionary only grows and the `ended` signal never fires for the ordinary case — so a HUD badge that hides on that signal never hides. This family has already shipped one recorder that grew without bound.

## What it deliberately does not do

It does not move anything, does not raycast, and does not know what health is. `can_see_fn` is supplied by the game because this addon has no opinion about which collision layers count and dot-physics already does.

It also does not replace dot-match's `DotSpawnPoint`/`DotSpawnSelector`, which stay where they are. Those are the match's own view — one point per player, picked by danger, dependency-free, enough for a deathmatch. Using both means deciding which one the match asks, and the game makes that call.
