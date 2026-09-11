@tool
class_name DotSpawnCondition
extends Resource

## A rule a site must satisfy, or a reason to prefer one site over another.
##
## [b]Two questions, not one, and keeping them apart is the whole design.[/b]
## [method allows] is a veto — this site is not a choice — and [method bonus] is an
## opinion — this site is a better choice. A condition that expresses a veto as a large
## penalty will still pick the forbidden site when it is the only one left, which is how
## a game ends up spawning the attacking team inside the defenders' base in the one
## round where it matters.
##
## Subclass this for anything a game needs that is not here. The four shipped subclasses
## are the four that every project writes.

## Named in logs and in [method DotSpawnDirector.describe_lines].
@export var id: StringName = &""

## Whether this condition is consulted at all.
@export var enabled: bool = true


## Whether [param site] is a legal choice for this request.
##
## [param context] is whatever [DotSpawnDirector] was given: [code]team[/code],
## [code]class[/code], [code]key[/code], [code]tick[/code], [code]enemies[/code] (an
## [Array] of [Vector3]), [code]friends[/code], [code]can_see[/code] (a [Callable]), and
## anything the game added.
func allows(_site: DotSpawnSite, _context: Dictionary) -> bool:
	return true


## How much better or worse this site is. Added to the score; zero is neutral.
func bonus(_site: DotSpawnSite, _context: Dictionary) -> float:
	return 0.0


## Why a site was rejected, for the log line that follows a fallback.
func reason() -> String:
	return String(id) if id != &"" else get_script().resource_path.get_file()


func describe() -> String:
	return "%s%s" % [reason(), "" if enabled else " (off)"]
