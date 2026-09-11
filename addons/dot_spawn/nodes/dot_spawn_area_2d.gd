@tool
class_name DotSpawnArea2D
extends Area2D

## A 2D volume things spawn inside, and — optionally — are safe inside.
##
## The 2D half of [DotSpawnArea3D]. Same contract, same [method protects_key] interface
## for a damage system, and a separate class for the same reason the markers are: an
## [Area2D] and an [Area3D] share no base below [Node], and a node that branched on
## which one it was would branch wrongly in the scene where it mattered.

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

@export var safe_zone: bool = false

@export var safe_from_world_damage: bool = false

@export var safe_for_owning_team_only: bool = true

@export_group("Placement")

## Half-extents in pixels, used when the area has no rectangle shape to measure.
@export var fallback_extents: Vector2 = Vector2(64.0, 64.0)

## `func(rng: RandomNumberGenerator) -> Transform2D`, replacing the box sample.
var sample_fn: Callable = Callable()

## `func(body: Node) -> String`, mapping a body that entered to a key.
var key_of: Callable = Callable()

var _inside: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func to_site() -> DotSpawnSite:
	var site := DotSpawnSite.new()
	site.id = site_id
	site.position = Vector3(global_position.x, global_position.y, 0.0)
	site.yaw = global_rotation
	site.team = team
	site.classes = classes.duplicate()
	site.priority = site_priority
	site.enabled = site_enabled
	var e := measured_extents()
	site.extents = Vector3(e.x, e.y, 0.0)
	site.cooldown_ticks = cooldown_ticks
	site.protects = safe_zone
	site.meta = meta.duplicate(true)
	site.occupants = _inside.size()
	site.is_2d = true
	return site


func measured_extents() -> Vector2:
	for child in get_children():
		var shape_node := child as CollisionShape2D

		if shape_node == null:
			continue

		var rect := shape_node.shape as RectangleShape2D

		if rect != null:
			# Half, because RectangleShape2D.size is the full size. The same trap as
			# the 3D one, and getting it wrong puts half the spawns outside the box
			# somebody drew.
			return (rect.size * 0.5) * shape_node.scale

	return fallback_extents


func sample(rng: RandomNumberGenerator) -> Transform2D:
	if sample_fn.is_valid():
		return sample_fn.call(rng) as Transform2D

	return to_site().sample_2d(rng)


func protects_key(key: String, attacker_team: StringName = &"", world_damage: bool = false) -> bool:
	if not safe_zone:
		return false

	if world_damage and not safe_from_world_damage:
		return false

	if not _inside.has(key):
		return false

	if safe_for_owning_team_only and team != &"":
		var victim_team := StringName(str(_inside[key]))
		if victim_team != &"" and victim_team != team:
			return false

	if attacker_team != &"" and attacker_team == team:
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


func _on_body_entered(body: Node2D) -> void:
	if not key_of.is_valid():
		return

	var key := str(key_of.call(body))

	if key == "":
		return

	var body_team := &""

	if body.has_method("spawn_team"):
		body_team = StringName(str(body.call("spawn_team")))

	note_entered(key, body_team)


func _on_body_exited(body: Node2D) -> void:
	if not key_of.is_valid():
		return

	var key := str(key_of.call(body))

	if key != "":
		note_left(key)


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var has_rect := false

	for child in get_children():
		var shape_node := child as CollisionShape2D
		if shape_node != null and shape_node.shape is RectangleShape2D:
			has_rect = true

	if not has_rect:
		out.append("No rectangle CollisionShape2D, so the fallback extents are used.")

	if safe_zone and team == &"" and safe_for_owning_team_only:
		out.append(
			"This is a safe zone restricted to its owning team, and it has no team. "
			+ "Nothing will ever be protected by it."
		)

	return out
