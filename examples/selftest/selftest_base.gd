extends Node

## Shared state and assertions for the dot-spawn self-test layers.

const RATE := 64

var _passed := 0
var _failed := 0
var _section_count := 0


func _director(rules: DotSpawnRules) -> DotSpawnDirector:
	var d := DotSpawnDirector.new()
	d.rules = rules
	d.tick_rate = RATE
	d.register_service = false
	add_child(d)
	return d


func _grid(count: int, team: StringName = &"") -> Array[DotSpawnSite]:
	var out: Array[DotSpawnSite] = []

	for i in range(count):
		out.append(DotSpawnSite.point(
			StringName("s%d" % i), Vector3(float(i) * 10.0, 0, 0), 0.0, team
		))

	return out


func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
