class_name DotSpawnProtection
extends RefCounted

## Who is briefly un-killable after entering the world, and when that stops.
##
## [b]A ledger, not a behaviour.[/b] It grants, expires and revokes; it never touches
## health, never subscribes to a damage signal and never knows what a weapon is. A
## damage system asks [method blocks] one question and gets one answer, which is what
## lets dot-combat use it without dot-spawn depending on dot-combat, and lets a game
## with neither use it for something else entirely.
##
## Counted in ticks throughout, like everything else in this family, because a wall
## clock and a simulation disagree about how long two seconds is exactly when it
## matters — under load, in the fight the protection was for.

# No log channel: a ledger asked once per hit and once per tick. Every change it makes
# is a signal (granted, ended with a reason), and a line per grant would be one per
# spawn; DotSpawnDirector, which decides the spawn, is what logs.

## Somebody's protection ended, and why: [code]&"expired"[/code],
## [code]&"attacked"[/code], [code]&"left"[/code], [code]&"moved"[/code] or [code]&"revoked"[/code].
signal ended(key: String, reason: StringName, tick: int)

## Granted.
signal granted(key: String, until_tick: int)

var rules: DotSpawnRules = null

## key -> the tick protection runs out on.
var _until: Dictionary = {}

## key -> the site id they spawned on, for the leave check.
var _origin: Dictionary = {}

## key -> where they were when protected, for the distance check. Absent when the grant
## gave no position, which turns the distance check off for that key.
var _anchor: Dictionary = {}


func _init(p_rules: DotSpawnRules = null) -> void:
	rules = p_rules if p_rules != null else DotSpawnRules.new()


## Protects [param key] for the rules' duration, starting now.
##
## Returns the tick it runs out on, or [param tick] itself when protection is off — so
## a caller can log the number without branching, and a zero-length grant is not a
## special case anywhere downstream.
func grant(key: String, tick: int, tick_rate: int, site_id: StringName = &"", position: Variant = null) -> int:
	var ticks := rules.protection_ticks(tick_rate)

	if ticks <= 0:
		_until.erase(key)
		_origin.erase(key)
		_anchor.erase(key)
		return tick

	var until := tick + ticks
	_until[key] = until
	_origin[key] = site_id

	if position is Vector3:
		_anchor[key] = position
	else:
		_anchor.erase(key)

	granted.emit(key, until)
	return until


## Whether [param key] is protected at [param tick].
func is_protected(key: String, tick: int) -> bool:
	if not _until.has(key):
		return false

	return tick < int(_until[key])


## Ticks of protection left, or 0.
func remaining(key: String, tick: int) -> int:
	if not _until.has(key):
		return 0

	return maxi(0, int(_until[key]) - tick)


## Whether protection should stop [param attacker] hurting [param victim].
##
## [b]This is the whole interface a damage system needs.[/b] It answers about the pair
## rather than about the victim alone, because the rules distinguish world damage —
## falling, drowning, a hurt volume — from another player's, and a protected player who
## walks into a pit is meant to die in it.
func blocks(attacker: String, victim: String, tick: int, world_damage: bool = false) -> bool:
	if not is_protected(victim, tick):
		return false

	if world_damage and rules.world_damage_ignores_protection:
		return false

	# Self damage is never blocked. A player who rocket-jumps out of their own spawn is
	# doing it on purpose, and protecting them from it turns a two-second window into a
	# free movement technique.
	if attacker == victim:
		return false

	return true


## Called when a protected thing attacks, which usually ends it.
##
## Returns whether protection actually ended, so a caller can put a line in the kill
## feed without asking twice.
func note_attack(key: String, tick: int) -> bool:
	if not rules.protection_breaks_on_attack:
		return false

	if not is_protected(key, tick):
		return false

	_end(key, &"attacked", tick)
	return true


## Called when a protected thing moves out of the site it spawned on.
func note_left_area(key: String, tick: int) -> bool:
	if not rules.protection_breaks_on_leaving:
		return false

	if not is_protected(key, tick):
		return false

	_end(key, &"left", tick)
	return true


## Called each tick with where a protected thing is now. Ends protection (reason
## [code]&"moved"[/code]) once it is further than the rules' distance from the position it
## was granted at. Returns whether protection ended.
func note_position(key: String, position: Vector3, tick: int) -> bool:
	if not rules.protection_breaks_on_distance or rules.protection_break_distance <= 0.0:
		return false

	if not _anchor.has(key) or not is_protected(key, tick):
		return false

	if (_anchor[key] as Vector3).distance_to(position) <= rules.protection_break_distance:
		return false

	_end(key, &"moved", tick)
	return true


func revoke(key: String, tick: int) -> void:
	if _until.has(key):
		_end(key, &"revoked", tick)


## Expires everybody whose time is up. Call once a tick.
##
## [b]Necessary even though [method is_protected] already compares against the tick.[/b]
## Without it the dictionary only ever grows, the [signal ended] signal never fires for
## the ordinary case, and a HUD that hides its protection badge on that signal keeps it
## up forever. This family has shipped a recorder that grew without bound already.
func advance(tick: int) -> void:
	var done: Array[String] = []

	for key: Variant in _until.keys():
		if tick >= int(_until[key]):
			done.append(String(key))

	for key in done:
		_end(key, &"expired", tick)


func clear() -> void:
	_until.clear()
	_origin.clear()
	_anchor.clear()


func protected_keys() -> PackedStringArray:
	var out := PackedStringArray()

	for key: Variant in _until.keys():
		out.append(String(key))

	out.sort()
	return out


func origin_site(key: String) -> StringName:
	return _origin.get(key, &"")


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("spawn protection: %.1f s%s%s" % [
		rules.protection_sec,
		", breaks on attack" if rules.protection_breaks_on_attack else "",
		", breaks on leaving" if rules.protection_breaks_on_leaving else "",
	])

	for key in protected_keys():
		out.append("  %s until tick %d" % [key, int(_until[key])])

	return out


func describe() -> String:
	return "DotSpawnProtection(%d protected)" % _until.size()


func _end(key: String, reason: StringName, tick: int) -> void:
	_until.erase(key)
	_origin.erase(key)
	_anchor.erase(key)
	ended.emit(key, reason, tick)
