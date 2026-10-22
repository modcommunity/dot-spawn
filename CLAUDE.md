# dot-spawn

Where anything enters the world, and why that place: sites as values, conditions that veto or score them, a deterministic pick with a loud fallback, respawn timing, and spawn protection as a ledger.

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/dot_spawn/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing anything: sites as values, vetoes vs opinions, `MetaMatchesRequest`, the fallback, one generator per request, node traps, protection, what it does not do |
| [docs/map-data-tools.md](docs/map-data-tools.md) | the planned mover watch and cull, strategies and spread, authored points, the map data store and bundle, admin tools: which addon owns each |

## Layout

| Path | What |
| --- | --- |
| `core/dot_spawn_site.gd` | `DotSpawnSite`: one candidate place, as a value (`extents` are half-extents, `last_used_tick`) |
| `core/dot_spawn_request.gd` | `DotSpawnRequest`: who is spawning, on which side, as what, when; `make(..., extra)` |
| `core/dot_spawn_choice.gd` | `DotSpawnChoice`: the answer, `fell_back`, `protected_until` |
| `core/dot_spawn_rules.gd` | `DotSpawnRules`: every policy, layered `DotConfig` |
| `core/dot_spawn_condition.gd` | `DotSpawnCondition`: the extension point, `allows()` (veto) and `bonus()` (opinion) |
| `core/dot_spawn_conditions.gd` | `MinimumEnemyDistance`, `OutOfSight`, `NotOccupied`, `MetaEquals`, `MetaMatchesRequest` |
| `core/dot_spawn_protection.gd` | `DotSpawnProtection`: who is briefly un-killable, `blocks`, `advance`, `ended` |
| `core/dot_spawn_watch.gd`, `dot_spawn_cull.gd`, `dot_spawn_cull_rules.gd` | `DotSpawnWatch` (stuck, off nav, fell out, unreachable, far verdicts, time-sliced), `DotSpawnCull` (one `DotSpawnDecision` per mover: nudge, teleport, despawn, kill), `DotSpawnCullRules` (`DOT_SPAWN_CULL_*`, `--cull-*`, off by default); the host applies decisions through callables |
| `nodes/` | `DotSpawnMarker3D`, `DotSpawnMarker2D`, `DotSpawnArea3D` (optionally a safe zone), `DotSpawnArea2D`; each has `to_site()` |
| `runtime/dot_spawn_director.gd` | `DotSpawnDirector`: `refresh`, `choose`, `choose_from`, respawn timing, `can_see_fn` |
| `examples/spawn_selftest.tscn` | the suite: no level loaded |

Paths except `examples/` are in `addons/dot_spawn/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/spawn_selftest.tscn`.

## Rules that bite

- Decide on `DotSpawnSite` values only; the tree is touched in `refresh`, which collects anything with `to_site()`. [design](docs/design.md#everything-that-decides-works-on-dotspawnsite-values)
- `refresh()` keeps each site's `last_used_tick`. [design](docs/design.md#everything-that-decides-works-on-dotspawnsite-values)
- A veto is `allows()`, never a large negative `bonus()`; a condition with no information has no opinion. [design](docs/design.md#vetoes-and-opinions-are-different-things)
- A request without the field `MetaMatchesRequest` reads matches every site; `make` duplicates `extra`. [design](docs/design.md#metamatchesrequest-a-site-against-the-request)
- The fallback is reported three ways; `validate()` refuses a distance floor with no fallback. [design](docs/design.md#the-fallback-is-not-optional)
- One generator per request from seed, tick and key; never a member stream. [design](docs/design.md#one-generator-per-request)
- Nodes use `site_priority` (areas own `priority`); `measured_extents` halves a box size. [design](docs/design.md#node-traps)
- Protection never touches health and never blocks self damage; call `advance()` or `ended` never fires. [design](docs/design.md#protection-is-a-ledger-not-a-behaviour)
- Protection is granted only inside `DotSpawnDirector.choose`: a game that places spawns itself has none. [design](docs/design.md#protection-is-a-ledger-not-a-behaviour)

Deliberately not here: moving, raycasting, health, replacing dot-match's simple spawn selector. [design](docs/design.md#what-it-deliberately-does-not-do)
