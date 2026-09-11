@tool
class_name DotSpawnConditions
extends RefCounted

## The four conditions every project writes, so that no project has to write them.
##
## Together in one file on purpose: they are eighty lines between them, they are read as
## a set, and four files each holding one twenty-line subclass is four files somebody has
## to find. Anything longer than these belongs in its own file, as
## [DotSpawnCondition] documents.


## A hard floor on how close an enemy may be.
##
## Distinct from the distance [i]weight[/i], which trades: this does not. There is a
## distance at which a spawn is not a bad spawn but a death, and no amount of scoring
## anywhere else should be able to buy it back.
class MinimumEnemyDistance extends DotSpawnCondition:
	var metres: float = 8.0

	func _init(p_metres: float = 8.0) -> void:
		metres = p_metres
		id = &"minimum_enemy_distance"

	func allows(site: DotSpawnSite, context: Dictionary) -> bool:
		if metres <= 0.0:
			return true

		var enemies: Array = context.get("enemies", [])
		var floor_sq := metres * metres

		for e: Variant in enemies:
			if site.position.distance_squared_to(e as Vector3) < floor_sq:
				return false

		return true

	func reason() -> String:
		return "an enemy is within %.1f m" % metres


## Refuses a site an enemy can currently see.
##
## Uses the [code]can_see[/code] callable out of the context rather than casting a ray
## itself, because this addon has no opinion about which collision layers count and
## dot-physics already does.
class OutOfSight extends DotSpawnCondition:
	## Whether being seen is a veto or merely a penalty.
	var hard: bool = false
	var penalty: float = 500.0

	func _init(p_hard: bool = false, p_penalty: float = 500.0) -> void:
		hard = p_hard
		penalty = p_penalty
		id = &"out_of_sight"

	func allows(site: DotSpawnSite, context: Dictionary) -> bool:
		if not hard:
			return true

		return not _seen(site, context)

	func bonus(site: DotSpawnSite, context: Dictionary) -> float:
		if hard:
			return 0.0

		return -penalty if _seen(site, context) else 0.0

	func _seen(site: DotSpawnSite, context: Dictionary) -> bool:
		var can_see: Variant = context.get("can_see", null)

		if not (can_see is Callable):
			return false

		var fn := can_see as Callable

		if not fn.is_valid():
			return false

		for e: Variant in context.get("enemies", []):
			if bool(fn.call(e as Vector3, site.position)):
				return true

		return false

	func reason() -> String:
		return "an enemy can see it"


## Penalises, or refuses, a site somebody is already standing on.
class NotOccupied extends DotSpawnCondition:
	var hard: bool = true

	func _init(p_hard: bool = true) -> void:
		hard = p_hard
		id = &"not_occupied"

	func allows(site: DotSpawnSite, _context: Dictionary) -> bool:
		# An area is big enough to hold several, which is the reason areas exist.
		if not hard or site.is_area():
			return true

		return site.occupants <= 0

	func bonus(site: DotSpawnSite, _context: Dictionary) -> float:
		return 0.0 if hard else -400.0 * float(site.occupants)

	func reason() -> String:
		return "something is standing on it"


## Requires the site to carry a metadata entry with a given value.
##
## The general-purpose escape hatch: a mapper tags a site
## [code]{"zone": "attackers"}[/code] and a game mode requires it, with nothing in this
## addon needing to know what a zone is.
class MetaEquals extends DotSpawnCondition:
	var key: String = ""
	var want: Variant = null

	func _init(p_key: String = "", p_want: Variant = null) -> void:
		key = p_key
		want = p_want
		id = StringName("meta_%s" % p_key)

	func allows(site: DotSpawnSite, _context: Dictionary) -> bool:
		if key == "":
			return true

		if not site.meta.has(key):
			return false

		# DotValue rather than ==: the two sides come from a level file and from game
		# code, so their Variant types are not under one author's control, and == on
		# mismatched types is a runtime error that abandons the expression.
		return DotValue.same(site.meta[key], want)

	func reason() -> String:
		return "its '%s' is not %s" % [key, str(want)]
