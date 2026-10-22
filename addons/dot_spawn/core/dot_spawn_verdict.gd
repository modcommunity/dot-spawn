class_name DotSpawnVerdict
extends RefCounted

## What the watch found wrong with one mover at one sample.

enum Category { FELL_OUT, STUCK, OFF_NAV, UNREACHABLE, FAR }

var id: Variant
var kind: StringName = &""
var category: int = Category.STUCK
## How long the condition has held, in seconds (zero for a fall).
var seconds: float = 0.0
var position: Vector3 = Vector3.ZERO
## The watch's clock when this was found.
var time: float = 0.0


static func category_name(c: int) -> String:
	match c:
		Category.FELL_OUT: return "fell_out"
		Category.STUCK: return "stuck"
		Category.OFF_NAV: return "off_nav"
		Category.UNREACHABLE: return "unreachable"
		Category.FAR: return "far"
	return "unknown"


func describe() -> String:
	return "%s %s %.1fs at %s" % [id, category_name(category), seconds, position.snappedf(0.1)]
