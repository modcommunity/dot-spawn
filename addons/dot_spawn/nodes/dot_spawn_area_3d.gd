@tool
class_name DotSpawnArea3D
extends Area3D

## A volume things spawn inside, and — optionally — are safe inside.
##
## [b]An area is not a bigger point.[/b] A point spawn works for one thing at a time and
## fails in the exact case a round begins: sixteen capsules at one coordinate, which the
## engine resolves by launching them. An area holds as many as it has room for, and the
## point inside it is picked per request rather than per site.
##
## The second half is the one worth designing carefully. An area can be a [b]safe
## zone[/b] — things standing in it take no damage — and that is a rule a damage system
## asks about rather than a rule this node enforces. [method protects_key] is the whole
## interface; dot-combat calls it, dot-spawn never calls dot-combat, and a game with
## neither can use it for a shop, a lobby or a finish line.
##
## [codeblock]
## # In a damage filter:
## if area.protects_key(victim_key):
##     return 0.0
## [/codeblock]

const CHANNEL := "spawn.area"

## Something the game recognises entered. The key comes from [member key_of], because
## only the game knows how a body maps to a player.
signal key_entered(key: String)
signal key_left(key: String)

@export var site_id: StringName = &"any"

@export var team: StringName = &""

@export var classes: Array[StringName] = []

## Higher wins a tie. A map's preferred start.
##
## [b]Not called [code]priority[/code].[/b] [Area2D] and [Area3D] already have one — the
## order overlapping areas are processed in — and GDScript refuses the collision with an
## error reported against the file that USES the property rather than against this one.
## The markers use the same name so that the four nodes read alike.
@export var site_priority: int = 0

@export var site_enabled: bool = true

@export_range(-1, 100000, 1) var cooldown_ticks: int = -1

@export var meta: Dictionary = {}

@export_group("Safety")

## Whether things inside this area are protected from damage.
##
## [b]Enforced by whoever deals damage, not here.[/b] An area that reached into a health
## system would be an area that only works with one health system.
@export var safe_zone: bool = false

## Whether protection also covers damage from the world — falling, drowning, a hazard.
##
## Off by default: a safe zone is protection from other players, and a player who walks
## into a pit inside one should still fall into it.
@export var safe_from_world_damage: bool = false

## Whether only the owning team is safe here.
##
## On for a base: an attacker who pushes into the defenders' spawn should be killable
## there, or the area becomes somewhere to stand and shoot from.
@export var safe_for_owning_team_only: bool = true

@export_group("Placement")

## Half-extents used when this area's own shape cannot be measured.
##
## A [CollisionShape3D] with a [BoxShape3D] is measured. Anything else — a capsule, a
## convex hull, a concave mesh — is not, because the honest bounding box of a concave
## shape contains places outside it and a spawn inside a wall is worse than a spawn in a
## slightly smaller box.
@export var fallback_extents: Vector3 = Vector3(2.0, 0.0, 2.0)

## `func(rng: RandomNumberGenerator) -> Transform3D`, replacing the box sample entirely.
##
## The customisation hook: a game that wants its spawn area to place things on a ring, a
## grid, or the nearest navmesh point assigns this and the rest of the addon is unaware.
var sample_fn: Callable = Callable()

## `func(body: Node) -> String`, mapping a body that entered to a key.
##
## Unset, the area still fires [signal body_entered] and tracks nothing, which is the
## correct behaviour for a game that only wants the placement half.
var key_of: Callable = Callable()

var _inside: Dictionary = {}

## Whether the missing-[member key_of] warning has been written, so it is written once.
var _warned_no_key: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# The editor says this in the scene tree; a dedicated server never opens one, so
	# the same configuration warning is said once more where an operator will see it.
	if safe_zone and team == &"" and safe_for_owning_team_only:
		DotLog.warn(CHANNEL, "a team-only safe zone has no team, so it protects nobody", {
			"area": String(site_id) if site_id != &"" else String(name),
		})


func to_site() -> DotSpawnSite:
	var site := DotSpawnSite.new()
	site.id = site_id
	site.position = global_position
	site.yaw = global_basis.get_euler().y
	site.team = team
	site.classes = classes.duplicate()
	site.priority = site_priority
	site.enabled = site_enabled
	site.extents = measured_extents()
	site.cooldown_ticks = cooldown_ticks
	site.protects = safe_zone
	site.meta = meta.duplicate(true)
	site.occupants = _inside.size()
	site.is_2d = false
	return site


## The half-extents of this area's own box shape, or [member fallback_extents].
func measured_extents() -> Vector3:
	for child in get_children():
		var shape_node := child as CollisionShape3D

		if shape_node == null:
			continue

		var box := shape_node.shape as BoxShape3D

		if box != null:
			# Half, because Godot's BoxShape3D.size is the full size and DotSpawnSite's
			# extents are half-extents. Getting this wrong doubles the area silently,
			# and half the spawns then land outside the volume that was drawn.
			return (box.size * 0.5) * shape_node.scale

	return fallback_extents


## Where inside this area a given request goes.
func sample(rng: RandomNumberGenerator) -> Transform3D:
	if sample_fn.is_valid():
		return sample_fn.call(rng) as Transform3D

	return to_site().sample(rng)


## Whether [param key] is inside and covered.
##
## The whole interface a damage system needs. Returns false for everything when the area
## is not a safe zone, so a caller can ask unconditionally.
func protects_key(key: String, attacker_team: StringName = &"", world_damage: bool = false) -> bool:
	if not safe_zone:
		return false

	if world_damage and not safe_from_world_damage:
		return false

	if not _inside.has(key):
		return false

	if safe_for_owning_team_only and team != &"":
		# The attacker's side is what decides, not the victim's: an attacker who has
		# pushed into the defenders' spawn is standing in a volume that is not theirs,
		# and being killable there is the point.
		var victim_team := StringName(str(_inside[key]))
		if victim_team != &"" and victim_team != team:
			return false

	if attacker_team != &"" and attacker_team == team:
		# Friendly fire inside your own spawn. Protection does not cover it, because a
		# team-mate blocking a doorway is a problem a game solves elsewhere and an
		# invulnerable one is worse.
		return false

	return true


func contains_key(key: String) -> bool:
	return _inside.has(key)


func occupant_count() -> int:
	return _inside.size()


func occupant_keys() -> PackedStringArray:
	var out := PackedStringArray()

	for key: Variant in _inside.keys():
		out.append(String(key))

	out.sort()
	return out


## Records somebody as inside without a physics body. For a headless server.
func note_entered(key: String, key_team: StringName = &"") -> void:
	if _inside.has(key):
		return

	_inside[key] = String(key_team)
	key_entered.emit(key)


func note_left(key: String) -> void:
	if not _inside.has(key):
		return

	_inside.erase(key)
	key_left.emit(key)


func clear_occupants() -> void:
	for key in occupant_keys():
		note_left(key)


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("area %s%s, %d inside" % [
		String(site_id),
		" (safe zone)" if safe_zone else "",
		_inside.size(),
	])

	for key in occupant_keys():
		out.append("  " + key)

	return out


func describe() -> String:
	return to_site().describe()


func _on_body_entered(body: Node3D) -> void:
	if not key_of.is_valid():
		# Once, and only for a safe zone: without key_of nothing that enters is ever an
		# occupant, so a zone drawn to protect people silently protects nobody. WARN,
		# because it is wiring a game forgot, and it looks exactly like working.
		if safe_zone and not _warned_no_key:
			_warned_no_key = true
			DotLog.warn(CHANNEL, "a safe zone has no key_of, so nothing inside it is protected", {
				"area": String(site_id) if site_id != &"" else String(name),
			})
		return

	var key := str(key_of.call(body))

	if key == "":
		return

	var body_team := &""

	if body.has_method("spawn_team"):
		body_team = StringName(str(body.call("spawn_team")))

	note_entered(key, body_team)


func _on_body_exited(body: Node3D) -> void:
	if not key_of.is_valid():
		return

	var key := str(key_of.call(body))

	if key != "":
		note_left(key)


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var has_box := false

	for child in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node != null and shape_node.shape is BoxShape3D:
			has_box = true

	if not has_box:
		out.append(
			"No box-shaped CollisionShape3D, so the fallback extents are used for "
			+ "placement. Any other shape is deliberately not measured: the bounding "
			+ "box of a concave volume contains places outside it, and a spawn inside "
			+ "a wall is worse than a spawn in a slightly smaller box."
		)

	if safe_zone and team == &"" and safe_for_owning_team_only:
		out.append(
			"This is a safe zone restricted to its owning team, and it has no team. "
			+ "Nothing will ever be protected by it."
		)

	return out
