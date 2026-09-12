class_name DotSpawnRequest
extends RefCounted

## Who is entering the world, on which side, as what, and when.
##
## A value rather than five parameters, because every one of them is optional in some
## game and a positional call with three empty strings in it is a call nobody can read.

## The thing being spawned. A player key, an NPC id, a prop's name.
var key: String = ""

## Which side. [code]&""[/code] for a game with no sides.
var team: StringName = &""

## Which class. Not [code]class[/code]: that is a reserved word in GDScript.
var player_class: StringName = &""

## The simulated tick this is happening on.
var tick: int = 0

## Anything a game's own conditions want. Reaches them as [code]context["extra"][/code].
var extra: Dictionary = {}


static func make(
	p_key: String,
	p_team: StringName = &"",
	p_class: StringName = &"",
	p_tick: int = 0,
	p_extra: Dictionary = {}
) -> DotSpawnRequest:
	var r := DotSpawnRequest.new()
	r.key = p_key
	r.team = p_team
	r.player_class = p_class
	r.tick = p_tick
	# Duplicated, not aliased. A caller that builds one dictionary and reuses it for
	# every request would otherwise have every request share — and mutate — one object,
	# which is the shape a per-player field is least expected to have.
	r.extra = p_extra.duplicate()
	return r


func describe() -> String:
	return "%s%s%s at tick %d" % [
		key,
		"" if team == &"" else " (%s)" % String(team),
		"" if player_class == &"" else " as %s" % String(player_class),
		tick,
	]


func _to_string() -> String:
	return "DotSpawnRequest(%s)" % describe()
