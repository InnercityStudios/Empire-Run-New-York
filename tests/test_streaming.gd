extends TestCase
## World rendering builders (run headless): shell, far city, chunk detail.

static var world: WorldLayout


func before_each() -> void:
	if world == null:
		var c := GameContent.load_default()
		world = WorldLayout.build(c.worlds["greater_new_york"], c)


func test_shell_builds_for_whole_world() -> void:
	var root := Node3D.new()
	var t := Time.get_ticks_msec()
	var stats := WorldShellBuilder.build(world, root)
	var ms := Time.get_ticks_msec() - t
	print("    shell: %d road chunk meshes in %d ms" % [stats["road_chunks"], ms])
	check(stats["road_chunks"] > 100, "roads cover the province")
	check(root.get_child_count() >= 6, "water, land, quays, roads, bridge, park, piers")
	root.free()


func test_far_city_covers_every_chunk_with_buildings() -> void:
	var t := Time.get_ticks_msec()
	var tris := 0
	var missing := 0
	for key in world.chunk_keys():
		var c := world.chunk(key)
		var mesh := FarCityBuilder.build_chunk(world, key, Content.db.building_catalog)
		if (not c["lots"].is_empty()) and mesh == null:
			missing += 1
		if mesh:
			tris += mesh.surface_get_array_len(0) / 3
	print("    far city: %d triangles for the whole province in %d ms" % [tris, Time.get_ticks_msec() - t])
	check_eq(missing, 0, "no chunk with buildings lacks a far LOD")
	check(tris < 300_000, "far city stays light (%d tris)" % tris)


func test_detail_chunk_for_little_italy() -> void:
	var key := world.chunk_of(Vector2(-80, 0))
	var t := Time.get_ticks_msec()
	var r := ChunkDetailBuilder.build(world, key)
	var ms := Time.get_ticks_msec() - t
	var built := ChunkDetailBuilder.to_mesh(r["surfaces"])
	print("    detail chunk %s: %d lots, %d tris, %d surfaces, merge %d ms" % [key, r["lots"], r["tris"],
		(built["names"] as PackedStringArray).size(), ms])
	check(built["mesh"] != null, "detail mesh built")
	check(r["lots"] > 20, "dense neighbourhood chunk")
	check((built["names"] as PackedStringArray).size() <= 24, "draw calls per chunk bounded by material count")
