class_name DotSpawnPointDef
extends RefCounted

## One authored spawn point with every setting, as plain data; `to_site()` makes the value the director decides on.
##
## Settings the site has no field for travel in `site.meta` under the `META_*` keys, where the point conditions in [DotSpawnConditions] read them.

const VERSION := 1

const KIND_PLAYER := &"player"
const KIND_NPC := &"npc"
const KIND_BOTH := &"both"
## Where a team's flag stands (and is captured); never a place to enter the world. `team` names whose.
const KIND_FLAG := &"flag"

const SIGHT_ANY := &"any"
const SIGHT_HIDDEN := &"hidden_from_players"
const SIGHT_VISIBLE := &"visible_to_players"

const SOURCE_MAP := &"map"
const SOURCE_AUTHORED := &"authored"
const SOURCE_GENERATED := &"generated"

const META_KIND := "pd_kind"
const META_GROUP := "pd_group"
const META_MAX_ALIVE := "pd_max_alive"
const META_PHASES := "pd_phases"
const META_SIGHT := "pd_sight"
const META_MIN_DIST := "pd_min_player_distance"
const META_MAX_DIST := "pd_max_player_distance"

var id: StringName = &"point"
var kind: StringName = KIND_BOTH
var enabled: bool = true
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
## Half-size of the area to spawn inside; zero is a point.
var radius: float = 0.0
var team: StringName = &""
var classes: Array[StringName] = []
## Points sharing a group spawn together.
var group: StringName = &""
## Relative chance among equals; zero never picks it.
var weight: float = 1.0
## Seconds after a use before the point scores well again; negative uses the rules' default.
var cooldown: float = -1.0
## Most things spawned here that may be alive at once; zero is unlimited.
var max_alive: int = 0
## Waves or match phases the point is live in; empty is always.
var phases: Array[StringName] = []
var sight: StringName = SIGHT_ANY
var min_player_distance: float = 0.0
## Zero is no ceiling.
var max_player_distance: float = 0.0
var source: StringName = SOURCE_AUTHORED
var meta: Dictionary = {}


## The site the director collects. [param tick_rate] converts `cooldown` seconds to ticks.
func to_site(tick_rate: int = 64) -> DotSpawnSite:
	var s := DotSpawnSite.point(id, position, yaw, team)
	s.classes = classes.duplicate()
	s.enabled = enabled
	s.weight = maxf(weight, 0.0)
	s.source = source
	s.extents = Vector3(radius, 0.0, radius) if radius > 0.0 else Vector3.ZERO
	s.cooldown_ticks = ceili(cooldown * float(tick_rate)) if cooldown >= 0.0 else -1
	s.meta = meta.duplicate(true)
	s.meta[META_KIND] = String(kind)
	s.meta[META_GROUP] = String(group)
	s.meta[META_MAX_ALIVE] = max_alive
	s.meta[META_PHASES] = _strings(phases)
	s.meta[META_SIGHT] = String(sight)
	s.meta[META_MIN_DIST] = min_player_distance
	s.meta[META_MAX_DIST] = max_player_distance
	return s


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"kind": String(kind),
		"enabled": enabled,
		"pos": [position.x, position.y, position.z],
		"yaw": yaw,
		"radius": radius,
		"team": String(team),
		"classes": _strings(classes),
		"group": String(group),
		"weight": weight,
		"cooldown": cooldown,
		"max_alive": max_alive,
		"phases": _strings(phases),
		"sight": String(sight),
		"min_player_distance": min_player_distance,
		"max_player_distance": max_player_distance,
		"source": String(source),
		"meta": meta.duplicate(true),
	}


## Reads a point; keys that are absent keep the defaults, so an older file loads.
static func from_dict(d: Dictionary) -> DotSpawnPointDef:
	var p := DotSpawnPointDef.new()
	p.id = StringName(str(d.get("id", "point")))
	p.kind = StringName(str(d.get("kind", "both")))
	p.enabled = bool(d.get("enabled", true))
	var pos: Variant = d.get("pos")

	if pos is Array and (pos as Array).size() == 3:
		p.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))

	p.yaw = float(d.get("yaw", 0.0))
	p.radius = maxf(float(d.get("radius", 0.0)), 0.0)
	p.team = StringName(str(d.get("team", "")))
	p.classes = _names(d.get("classes"))
	p.group = StringName(str(d.get("group", "")))
	p.weight = maxf(float(d.get("weight", 1.0)), 0.0)
	p.cooldown = float(d.get("cooldown", -1.0))
	p.max_alive = maxi(int(d.get("max_alive", 0)), 0)
	p.phases = _names(d.get("phases"))
	p.sight = StringName(str(d.get("sight", "any")))
	p.min_player_distance = maxf(float(d.get("min_player_distance", 0.0)), 0.0)
	p.max_player_distance = maxf(float(d.get("max_player_distance", 0.0)), 0.0)
	p.source = StringName(str(d.get("source", "authored")))
	var m: Variant = d.get("meta")
	p.meta = (m as Dictionary).duplicate(true) if m is Dictionary else {}
	return p


## What is wrong with the point, or an empty string.
func problem() -> String:
	if id == &"":
		return "a point needs an id"

	if not [KIND_PLAYER, KIND_NPC, KIND_BOTH, KIND_FLAG].has(kind):
		return "unknown kind '%s'" % kind

	if kind == KIND_FLAG and team == &"":
		return "a flag spawn needs a team"

	if not [SIGHT_ANY, SIGHT_HIDDEN, SIGHT_VISIBLE].has(sight):
		return "unknown sight rule '%s'" % sight

	if not [SOURCE_MAP, SOURCE_AUTHORED, SOURCE_GENERATED].has(source):
		return "unknown source '%s'" % source

	if max_player_distance > 0.0 and max_player_distance < min_player_distance:
		return "max_player_distance is below min_player_distance"

	return ""


## The editor form: one entry per setting, in [DotProfileSet.field] shape plus `choices` for enums.
static func schema() -> Array:
	return [
		DotProfileSet.field("id", "string", "point"),
		DotProfileSet.field("kind", "string", "both", {"choices": ["player", "npc", "both", "flag"]}),
		DotProfileSet.field("enabled", "bool", true),
		DotProfileSet.field("pos", "vec3", [0.0, 0.0, 0.0]),
		DotProfileSet.field("yaw", "float", 0.0),
		DotProfileSet.field("radius", "float", 0.0, {"min": 0.0}),
		DotProfileSet.field("team", "string", ""),
		DotProfileSet.field("classes", "list", []),
		DotProfileSet.field("group", "string", ""),
		DotProfileSet.field("weight", "float", 1.0, {"min": 0.0}),
		DotProfileSet.field("cooldown", "float", -1.0),
		DotProfileSet.field("max_alive", "int", 0, {"min": 0}),
		DotProfileSet.field("phases", "list", []),
		DotProfileSet.field("sight", "string", "any", {"choices": ["any", "hidden_from_players", "visible_to_players"]}),
		DotProfileSet.field("min_player_distance", "float", 0.0, {"min": 0.0}),
		DotProfileSet.field("max_player_distance", "float", 0.0, {"min": 0.0}),
		DotProfileSet.field("source", "string", "authored", {"choices": ["map", "authored", "generated"]}),
		DotProfileSet.field("meta", "dict", {}),
	]


static func _strings(a: Array) -> Array:
	var out: Array = []

	for x: Variant in a:
		out.append(str(x))

	return out


static func _names(v: Variant) -> Array[StringName]:
	var out: Array[StringName] = []

	if v is Array:
		for x: Variant in v:
			out.append(StringName(str(x)))

	return out
