# Map data tools: spawns, stragglers, soak tests and sharing

The plan for six connected pieces: a headless bot soak test per game, automatic culling of stuck or lost movers, in-game admin editing of player and NPC spawn points, spawn strategies that spread players over the whole map, one store for a map's spawns and navigation (disk or remote), and one JSON file that carries all of it between servers. This file is the design; the work is filed as nightly tasks named in each section.

## Where each piece lives

| Piece | Owner | Why there |
| --- | --- | --- |
| Point definitions, strategies, spread, NPC site rules | dot-spawn | Choosing a place is what dot-spawn is; it already has sites, conditions, modes and the fallback |
| Mover watch (stuck, off nav, fell out, unreachable) and the cull rule | dot-spawn | The other end of a spawn: who leaves the world, and where a relocated mover goes back in. Depends on dot-core only, so bots and NPCs can both feed it |
| Soak harness and its report | dot-bot | Every game with bots links dot-bot; the harness drives a game through a duck-typed adapter and takes the watch the same way, so dot-bot keeps its dot-core-only dependency |
| Map data bundle, store interface, stores | dot-map | The bundle is keyed by map id and version and ships beside the map in its pack; dot-map owns both |
| Nav rebake and hand links as data | dot-bot (`DotBotNav`), dot-npc-ai (`DotNpcAiNavAnnotations`) | They own the mesh and the links; they gain add, remove and `to_dict` for hand-made links, nothing more |
| Admin commands and the edit overlay | dot-game | The wiring every game repeats; it already reaches dot-server's admin flags and the console and chat command hosts |
| NPC director using authored sites | dot-npc-ai-director | Its `spawn_points` today are bare positions; it gains a per-site rule callable |
| Wiring | each game | A few lines: hand the director its sites, the watch its movers, the harness its adapter |

Nothing here needs a new addon, and no game keeps its own copy of any of it. game-zombie-zone's `tools/stuck_meter.gd`, `game/zz_unstick.gd`, `_fell_out` and `clear_wave_stragglers` are the measured prototypes and are retired into dot-spawn.

## The mover watch

`DotSpawnWatch` is fed once a tick with each mover's id, position, kind and whether it has somewhere to go, and samples every half second. It decides on values and touches no tree, like the rest of dot-spawn. A mover is **stuck** when it has a goal and has not left a 0.75 m circle in four seconds; a mover without a goal (idle, fighting, at its post, waiting at a shut door) is never stuck, because counting a holder at its post makes every map read the same. The other verdicts come from callables the game supplies, because dot-spawn knows no navigation: **off nav** (`nav_distance_fn` farther than a set distance from the mesh or graph), **fell out** (below the map's kill height, or a non-finite position), **unreachable** (`reachable_fn`: no path from any living player, which is how a straggler behind a closed gate is told apart from one that is merely far), and **far** (farther than a set distance from every player, for a set time).

It keeps what the soak test reports: seconds with a goal and seconds stuck per kind, the longest single stretch, every mover ever stuck, and the spots where stretches happened (rounded, counted, worst first), plus coverage: the cells of a grid the movers have stood in, against a total the game gives from its nav area.

## The cull rule

`DotSpawnCull` turns verdicts into actions through `DotSpawnCullRules`, layered `DotConfig` like every rule set (`sv_cull_*`, `DOT_SPAWN_CULL_*`, `--cull-*`). Per kind and per verdict: an action (`none`, `nudge`, `relocate`, `despawn`, `kill`), a threshold in seconds or metres, and whether a player can see the mover (a culled zombie that vanishes in front of somebody is a bug report; the default refuses `despawn` and `relocate` while seen and waits). dot-spawn still moves nothing and raycasts nothing ([design](design.md#what-it-deliberately-does-not-do)): the cull returns the action and the game applies it through `nudge_fn`, `teleport_fn`, `despawn_fn` and `kill_fn`. `nudge` is the step zombie-zone's unstick takes: under a metre along the way it was going, only into free space with floor under it and nothing solid between. `relocate` asks the spawn director for an NPC site (so every site rule applies) and hands it to `teleport_fn`. `despawn` removes without a death; `kill` goes through damage so kill feeds and wave counts see it. A despawned wave member is owed again, which is the game's callback (`on_culled(id, verdict, action)`), because only the game knows what a wave owes.

Escalation is the default: a stuck mover is nudged twice, then relocated, then despawned; one that fell out is despawned at once; an unreachable or far one is relocated after a grace period. Every action is a DEBUG line with the mover, the verdict and where it stood, and a counter in `describe()`, so a map that culls a lot is visible as a map problem rather than hidden by the cure.

## The soak test

`DotBotSoak` plays one map for a few minutes of simulated time, headless, at a fixed tick and as fast as the machine runs one. It owns the clock, the seed, the duration, the watch and the report; the game supplies an adapter with `load_map(id)`, `add_bots(n)`, `step(delta)`, `movers()`, and `events()` for kills, deaths and objectives. The report is a table per kind (stuck share, longest stretch, worst spots, coverage percent, kills and deaths per minute, culls by verdict) and a final `SOAK {...}` line as JSON, so two runs compare with a diff and a change is measured instead of argued. Bands live in the game's repository (`tests/soak_bands.json`, per map); a run outside a band fails, like `headless_bots` today.

Each game adds `examples/bot_soak.tscn` (its `./game.sh test` suite, one short map) and `tools/bot_soak.gd` for long runs (`--map`, `--minutes`, `--bots`, `--seed`, `--set key=value`). The cull runs inside the soak in both modes: with actions off it measures the map, with them on it measures what players would see.

## Spawn points as authored data

`DotSpawnPointDef` is one authored point with every setting, and `to_site()` like the marker nodes, so the director collects it unchanged. Settings: `id`, `kind` (`player`, `npc`, `both`), `enabled`, `position`, `yaw` (facing), `radius` (an area when above zero), `team`, `classes` (player classes or NPC types), `group` (points that spawn together), `weight` (relative chance among equals), `cooldown` (seconds), `max_alive` (spawned from this point and still living), `phases` (waves or match phases it is live in; empty is always), `sight` (`any`, `hidden_from_players`, `visible_to_players`), `min_player_distance`, `max_player_distance`, `source` (`map`, `authored`, `generated`) and `meta` for anything a game adds. Each setting is enforced by a condition in `DotSpawnConditions` (vetoes for hard rules, `bonus` for weight), so nothing in the selector special-cases a field. `DotSpawnPointSet` holds them with `to_dict` and `from_dict`, versioned.

**The map's own spawns stay.** A map's declared spawns (its document's `spawns`, or converted spawn entities) become points with `source = map` every load; the authored set can disable one, override its settings by id, or add more, and never edits the map itself. Removing every authored point gives back exactly what the map shipped.

## Spawn strategies

A strategy is the policy over the pool; `DotSpawnRules.strategy` names an ordered list, and the first that yields a site wins, with the existing fallback (loud, three ways) after the last.

- `map`: only `source = map` sites, chosen by the existing modes. Everyone in the start room, as today.
- `spread`: players spawning together go to different parts of the map. Picks are made as a batch (`choose_batch`), each the site farthest from every pick so far and from living team-mates, with `spread_distance` as the floor; the floor halves (to `spread_min`) before the strategy gives up. By default the floor is only logged and the farthest site wins; `spread_floor_steers` makes the pick prefer sites meeting the floor (the mode chooses among them) and fall back to the farthest, logged. Enemy distance and sight conditions still veto.
- `grouped`: built. A team (or `extra["group"]` on the request) spawns together: the group's first request anchors it (anchors spread from each other), the rest take unused sites within `group_radius` of the anchor, else the nearest unused. Deterministic for the same seed and tick; read by `choose_batch`.
- `near_team`, `far_from_enemies`: the existing `NEAREST_FRIEND` and `FURTHEST` modes, named.

A map whose authors only placed a start room has nothing to spread over, so the pool can also take `generated` sites: a game hands `generate_fn` that returns points over its navigation (an even spread with clearance, from `DotBotNav.random_point` or the dot-npc graph, as zombie-zone already does for its NPCs), cached per map id and version. Settings: `spawn_strategy` (default `map`, so nothing changes until a game opts in), `spawn_spread_distance`, `spawn_spread_min`, `spawn_generate` (`off`, `when_few`, `always`), `spawn_generate_count`, `spawn_generate_clearance`.

## The store

`DotMapDataStore` in dot-map, with the shape of every store in the family: each method returns a `DotResult` and may be a coroutine, the base refuses what it does not implement. `load(game, map_id, map_version)`, `save(bundle, by)`, `list(game, map_id)`, `remove(...)`. Implementations: memory (tests), file (`user://map_data/<game>/<map_id>/<version>.json`, with `DotWeb.sync_filesystem()` after a write), pack (read-only, the bundle shipped inside the map's pack), sql (one table keyed by game, map id, version and section, through dot-sql, schema beside it as the other stores do) and http (the backbone API, through `HTTPRequest`). Configuration is layered as always: `map_data_store` (`file`, `sql`, `http`), `map_data_path`, `map_data_url`; a token for http is a sensitive key and is refused from the environment and argv.

Reading layers the sources: the pack's bundle is the default, the store's is the override, section by section. Keying by map version means an edited map does not inherit spawns placed for its old geometry; `load` falls back to the newest older version with a warning and marks the result `stale`, and the editor offers to keep or drop it.

## The bundle and sharing

One JSON file carries a map's tool data: `{"format": "dot-map-data", "schema": 1, "game", "map": {"id", "version", "digest"}, "meta": {"author", "created", "note"}, "sections": {...}}`. Sections are opaque dictionaries owned by their producers: `spawns` (dot-spawn's point set), `nav_settings` (the bake's agent and mask), `nav_links` (hand-made links: ladder, door, jump, drop, with both ends and flags), `nav_annotations` (the generated annotations, optional because they are a cache) and `cull` (the map's cull overrides). The baked mesh is not exported: it is rebuilt deterministically from the colliders and the settings, and a mesh is the largest and least portable part.

An imported file is untrusted input. Import checks the format and schema, refuses a different map id, warns on a different version or geometry digest and needs `force`, caps every count and string length, keeps only known section names, and never carries a script path or resource path that is loaded. Commands: `mapdata_export [path]` and `mapdata_import <path> [force]` on the server, and the same as a file save and open in the overlay.

## The admin tools

dot-game installs one command set, duck-typed on the console and chat hosts like dot-moderation's tool commands, gated by a dot-server admin flag (`map_edit_flag`, default the staff flag): `spawn_list`, `spawn_add <kind> [key=value...]` at the admin's feet and facing, `spawn_set <id> key=value...`, `spawn_remove <id>`, `spawn_toggle <id>`, `spawn_test <id>` (spawn the admin there), `spawn_strategy <name>`, `nav_rebake`, `nav_link_add <kind>` from a marked point to the admin's position, `nav_link_remove <id>`, `mapdata_save`, `mapdata_revert`, `mapdata_export`, `mapdata_import`. Every edit is validated server side and logged at INFO with the admin's id, because an admin moving spawns is something another admin wants to read later.

The client half is an overlay any admin can toggle: markers for every point (colour by kind and team, a disc for the radius, an arrow for facing, greyed when disabled), the nav links and, on request, the mesh; a point picked by looking at it opens a panel with every setting as a form, built from the point definition's own schema so a new setting needs no UI change. The toolgun in the sandbox game becomes a thin mode over the same commands, so there is one editor with two ways to point at things.

`nav-admin-rebake-tool` is this plan's navigation half: it adds the rebake and the link data in dot-bot and dot-npc-ai, and the commands and overlay here call them.

## Tasks

| Key | Repo | Size | After |
| --- | --- | --- | --- |
| `spawn-watch-cull` | dot-spawn | M | |
| `bot-soak-harness` | dot-bot | M | `spawn-watch-cull` |
| `zz-watch-cull-wire` | game-zombie-zone | S | `spawn-watch-cull` |
| `soak-arena` | game-arena | S | `bot-soak-harness` |
| `soak-zombie-zone` | game-zombie-zone | S | `soak-arena`, `zz-watch-cull-wire` |
| `soak-rollout` | the other games with bots, one builder each | S each | `soak-arena` |
| `spawn-spread-strategy` | dot-spawn | M | `spawn-watch-cull` |
| `spawn-point-defs` | dot-spawn | M | `spawn-spread-strategy` |
| `map-data-store` | dot-map | M | `spawn-point-defs` |
| `map-data-remote` | dot-map | M | `map-data-store` |
| `map-data-backbone-api` | website-city | M | `map-data-store` |
| `nav-admin-rebake-tool` | dot-bot, dot-npc-ai | M | `nav-doors-ladders` |
| `map-edit-commands` | dot-game | L | `map-data-store`, `nav-admin-rebake-tool` |
| `map-edit-overlay` | dot-game | M | `map-edit-commands` |
| `npc-director-sites` | dot-npc-ai-director | M | `spawn-point-defs` |
| `playground-spawn-tool` | game-playground | S | `map-edit-commands` |

## Open questions

- Should `spread` be the default strategy for the whole-map modes once it exists, or stay opt-in per game and per mode?
- Is remote storage meant to be shared across servers (one community's edits seen everywhere, through the backbone) or per server (dot-sql on that server's own database)? Both are planned; the backbone half is the one with a site endpoint to build.
- Who may edit: the existing staff flag, a new map-editor flag, or the map's author on the site as well?
- Should a shared bundle be uploadable to the site as content (listed, rated, installed in one click like a map), or is a file passed by hand enough for now?
- Is a culled NPC killed (counts as a kill, drops loot) or despawned (no trace) by default in each game?
- How long should the per-commit soak be: one short map in `./game.sh test`, with the long runs on the GPU boxes only?
