extends "res://examples/selftest/strategy_tests.gd"

## The marker and area node sections.


func _test_markers() -> void:
	_section("markers")

	var m := DotSpawnMarker3D.new()
	m.site_id = &"red_start"
	m.team = &"red"
	m.site_priority = 3
	m.position = Vector3(5, 0, -5)
	m.rotation = Vector3(0, PI * 0.5, 0)
	add_child(m)

	var site := m.to_site()
	_check(site.id == &"red_start", "a marker produces a site")
	_check(site.position.is_equal_approx(Vector3(5, 0, -5)), "at its own position")
	_check(is_equal_approx(site.yaw, PI * 0.5), "facing the way it faces")
	_check(site.priority == 3, "with its priority")
	_check(not site.is_2d, "and marked as 3D")

	m.position = Vector3(50, 0, 0)
	_check(
		m.to_site().position.is_equal_approx(Vector3(50, 0, 0)),
		"and recomputes every time — a marker on a moving platform that cached would "
		+ "hand out where the lift was two minutes ago"
	)

	var m2 := DotSpawnMarker2D.new()
	m2.site_id = &"flat"
	m2.position = Vector2(11, 22)
	add_child(m2)
	var site2 := m2.to_site()
	_check(site2.is_2d, "a 2D marker produces a 2D site")
	_check(site2.position_2d() == Vector2(11, 22), "at its pixel position")

	var blank := DotSpawnMarker3D.new()
	blank.site_id = &""
	add_child(blank)
	_check(
		not blank._get_configuration_warnings().is_empty(),
		"a marker with no id warns in the editor, where the mistake has no runtime "
		+ "symptom at all"
	)

	# Collection through the director, which is the only part that walks a tree.
	var holder := Node3D.new()
	add_child(holder)
	for i in range(4):
		var mk := DotSpawnMarker3D.new()
		mk.site_id = StringName("p%d" % i)
		mk.position = Vector3(float(i), 0, 0)
		holder.add_child(mk)

	var d := _director(DotSpawnRules.new())
	d.sites_ref = DotNodeRef.of_path(holder.get_path())
	d.refresh(false)
	_check(d.sites().size() == 4, "a director collects the markers under its root")

	var code_site := DotSpawnSite.point(&"runtime", Vector3.ONE)
	d.add_site(code_site)
	_check(d.sites().size() == 5, "and takes sites built in code")
	_check(d.remove_site(&"runtime") == 1, "which can be removed again")

	# The history that must survive a refresh.
	d.sites()[0].last_used_tick = 500
	d.refresh(false)
	_check(
		d.sites()[0].last_used_tick == 500,
		"a refresh keeps each site's cooldown history — resetting it on any refresh is "
		+ "a bug that only appears under load"
	)

	d.clear_sites()
	_check(d.sites().is_empty(), "and everything can be cleared")

	m.queue_free()
	m2.queue_free()
	blank.queue_free()
	holder.queue_free()
	d.queue_free()


func _test_areas() -> void:
	_section("areas")

	var area := DotSpawnArea3D.new()
	area.site_id = &"red_base"
	area.team = &"red"
	area.safe_zone = true
	area.fallback_extents = Vector3(4, 0, 4)
	add_child(area)

	var site := area.to_site()
	_check(site.is_area(), "an area produces an area site")
	_check(site.extents.is_equal_approx(Vector3(4, 0, 4)), "with the fallback extents")
	_check(site.protects, "marked as protecting")

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 2, 10)
	shape.shape = box
	area.add_child(shape)
	_check(
		area.measured_extents().is_equal_approx(Vector3(5, 1, 5)),
		"and a box shape is measured as half its size — the other reading doubles the "
		+ "area silently and puts half the spawns outside the volume that was drawn"
	)

	_check(not area.protects_key("ada"), "nobody is protected before entering")
	area.note_entered("ada", &"red")
	_check(area.contains_key("ada"), "somebody can be recorded as inside")
	_check(area.occupant_count() == 1, "and counted")
	_check(area.protects_key("ada"), "and is then protected")
	_check(
		not area.protects_key("ada", &"", true),
		"but not from the world, because a safe zone is protection from other players "
		+ "and a player who walks into a pit inside one should fall into it"
	)
	_check(
		not area.protects_key("ada", &"red"),
		"and not from their own side"
	)

	area.note_entered("bob", &"blue")
	_check(
		not area.protects_key("bob"),
		"an attacker standing in the defenders' spawn is killable there, or the area "
		+ "becomes somewhere to stand and shoot from"
	)

	_check(area.to_site().occupants == 2, "the site carries the occupancy")
	area.note_left("ada")
	_check(not area.contains_key("ada"), "leaving is recorded")
	_check(not area.protects_key("ada"), "and the protection goes with it")

	area.safe_zone = false
	area.note_entered("mel", &"red")
	_check(
		not area.protects_key("mel"),
		"an area that is not a safe zone protects nobody, so a damage system can ask "
		+ "unconditionally"
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placed := area.sample(rng)
	_check(
		absf(placed.origin.x - area.global_position.x) <= 5.01,
		"and it places things inside itself"
	)

	area.sample_fn = func(_r: RandomNumberGenerator) -> Transform3D:
		return Transform3D(Basis.IDENTITY, Vector3(99, 99, 99))
	_check(
		area.sample(rng).origin.is_equal_approx(Vector3(99, 99, 99)),
		"a game can replace the placement entirely, which is the customisation hook a "
		+ "ring, a grid or a navmesh snap needs"
	)

	var flat := DotSpawnArea2D.new()
	flat.site_id = &"lobby"
	flat.fallback_extents = Vector2(32, 32)
	add_child(flat)
	_check(flat.to_site().is_2d, "there is a 2D area too")
	_check(flat.to_site().extents.is_equal_approx(Vector3(32, 32, 0)), "with 2D extents")
	flat.note_entered("ada")
	_check(flat.occupant_keys().size() == 1, "which tracks occupants the same way")
	flat.clear_occupants()
	_check(flat.occupant_count() == 0, "and clears them")

	_check(area.describe_lines().size() >= 1, "an area describes itself")
	var unshaped := DotSpawnArea3D.new()
	_check(
		not unshaped._get_configuration_warnings().is_empty(),
		"and warns in the editor when it has no box to measure"
	)
	unshaped.free()

	# Freed rather than queued: the suite quits on the next line and a deferred free
	# never runs, which shows up as "RID allocations were leaked at exit" in a stderr
	# this family's own rules say to read.
	area.free()
	flat.free()
