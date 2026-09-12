@tool
class_name DotSpawnConditions
extends RefCounted

## The five conditions every project writes, so that no project has to write them.
##
## Together in one file on purpose: they are a hundred lines between them, they are read
## as a set, and five files each holding one twenty-line subclass is five files somebody
## has to find. Anything longer than these belongs in its own file, as
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


## Refuses a site whose meta does not match what the [b]request[/b] asked for.
##
## [b][MetaEquals]'s sibling, and the difference is where the wanted value comes
## from.[/b] `MetaEquals` compares a site against a constant fixed when the condition was
## built — "this director only ever spawns people at an attacker site". This one compares
## it against a field of the request, so one director can serve a question whose answer is
## different per player.
##
## That is the case every game with more than one kind of entry point has and none of the
## other four covers: a timer course where each track starts somewhere else, an objective
## mode where a site belongs to a point, a squad that spawns together, a class with its
## own door. Without it a game either builds one director per answer or picks the site
## itself and leaves the director choosing nothing — which is what happens in practice,
## because picking it yourself is one line.
##
## [codeblock]
## spawns.conditions = [DotSpawnConditions.MetaMatchesRequest.new("track")]
## spawns.choose(DotSpawnRequest.make(key, team, klass, tick, {"track": 2}))
## [/codeblock]
##
## A request that does not carry the field at all matches [b]every[/b] site rather than
## none, because "I did not ask" is not "I asked for nothing" — a caller with no opinion
## about the track wants the ordinary selection over all of them, and refusing everything
## would make an unasked question a map with no spawns.
class MetaMatchesRequest extends DotSpawnCondition:
	## The site meta key, and by default the request `extra` key as well.
	var key: String = ""

	## The request's `extra` key, when it differs from the site's.
	var request_key: String = ""

	## Whether a site missing the key is refused. Off: a site with no opinion is usable
	## by anybody, which is what a general-purpose site in a map full of specific ones is.
	var require_site_meta: bool = false

	func _init(
		p_key: String = "", p_request_key: String = "", p_require: bool = false
	) -> void:
		key = p_key
		request_key = p_request_key
		require_site_meta = p_require
		id = StringName("meta_matches_%s" % p_key)

	func allows(site: DotSpawnSite, context: Dictionary) -> bool:
		if key == "":
			return true

		var from_request: String = request_key if request_key != "" else key
		var extra: Dictionary = context.get("extra", {})

		if not extra.has(from_request):
			return true

		if not site.meta.has(key):
			return not require_site_meta

		# DotValue rather than ==, for [MetaEquals]' reason: one side comes from a level
		# file and the other from game code, and == on two different Variant types is a
		# runtime error that abandons the whole expression rather than answering false.
		return DotValue.same(site.meta[key], extra[from_request])

	func reason() -> String:
		return "its '%s' is not the one the request asked for" % key
