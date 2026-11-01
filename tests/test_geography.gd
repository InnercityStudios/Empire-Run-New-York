extends TestCase
## Greater New York 1977 geography world: Little Italy preservation, road
## connectivity across boroughs and bridges, determinism, streaming builders
## and save migration from the first province.

static var content: GameContent
static var world: WorldLayout
static var roads: RoadGraph
static var locs: Dictionary
static var build_ms := 0

const T0 := 1_700_000_000_000


func before_each() -> void:
	if world == null:
		content = GameContent.load_default()
		var t := Time.get_ticks_msec()
		world = WorldLayout.build(content.worlds["nyc_1977"], content)
		build_ms = Time.get_ticks_msec() - t
		roads = SimBootstrap.roads_for(world)
		locs = SimBootstrap.landmark_locations(world, roads)
		print("    nyc_1977: %d blocks, %d lots, %d nodes, %d edges, %d chunks, %d backdrop boxes in %d ms" % [
			world.blocks.size(), world.lots.size(), world.graph_nodes.size(), world.graph_edges.size(),
			world.chunk_keys().size(), world.backdrop_boxes.size(), build_ms])


func test_little_italy_preserved() -> void:
	var li: DistrictLayout = world.regions[0]["layout"]
	check_eq(LayoutFingerprint.of(li), "381:708f77ce754b9eda", "Little Italy lots unchanged")
	check_eq(world.lots.size(), 381, "only Little Italy stores lots (others are generated on demand)")
	var alone := DistrictLayout.build(content.districts["little_italy"], content.building_catalog)
	for id in alone.landmarks:
		check(world.landmarks.has(id), "landmark %s present" % id)
		check_eq(world.landmarks[id]["frontage"], alone.landmarks[id]["frontage"], "landmark %s frontage unmoved" % id)
	# Every road of the original district exists with the same node keys.
	var standalone := SimBootstrap.roads_for(alone)
	var missing := 0
	for e in standalone.edges:
		var a := roads.find_node(standalone.nodes[e["a"]])
		var b := roads.find_node(standalone.nodes[e["b"]])
		if a < 0 or b < 0 or not roads.location_from_key(standalone.location_to_key({"edge": standalone.edges.find(e), "offset": 0})).size():
			missing += 1
	check_eq(missing, 0, "Little Italy road edges keep their node keys")


func test_network_fully_connected() -> void:
	var seen := {0: true}
	var stack := [0]
	while not stack.is_empty():
		var n: int = stack.pop_back()
		for adj in roads.neighbours(n):
			if not seen.has(adj[1]):
				seen[adj[1]] = true
				stack.append(adj[1])
	check_eq(seen.size(), roads.nodes.size(), "every road node reachable from Little Italy")


func _route_to(p: Vector2) -> Dictionary:
	return roads.route(locs["lm_hq_marino"], roads.locate(Vector2i(roundi(p.x * 100), roundi(p.y * 100))))


func _crosses_bridge(r: Dictionary, bridge_id: String) -> bool:
	for br in world.bridge_paths:
		if br["id"] != bridge_id:
			continue
		var path: PackedVector2Array = br["path"]
		var mid := GeographyBuilder._along(path, br["length"] * 0.5)
		var pts: Array = r["points"]
		for i in pts.size() - 1:
			var a := Vector2(pts[i]) / 100.0
			var b := Vector2(pts[i + 1]) / 100.0
			if mid.distance_to(Geometry2D.get_closest_point_to_segment(mid, a, b)) < 40.0:
				return true
	return false


func test_little_italy_to_williamsburg_over_the_river() -> void:
	var t := Time.get_ticks_msec()
	var r := _route_to(Vector2(2350, -150))
	var ms := Time.get_ticks_msec() - t
	check(not r.is_empty(), "route to Williamsburg")
	if r.is_empty():
		return
	var over_bridge := _crosses_bridge(r, "williamsburg_bridge") or _crosses_bridge(r, "manhattan_bridge")
	check(over_bridge, "route crosses the East River by bridge")
	check(r["length"] > 2000_00 and r["length"] < 6000_00, "plausible length (%d m)" % (r["length"] / 100))
	check(ms < 250, "routing time %d ms" % ms)


func test_every_borough_reachable() -> void:
	for target in [["Brooklyn Heights", Vector2(1450, 1700)], ["Bed-Stuy", Vector2(3300, 1350)],
			["Long Island City", Vector2(2850, -2250)], ["Flushing", Vector2(7000, -3300)],
			["Harlem", Vector2(2050, -4800)], ["South Bronx", Vector2(3600, -5700)], ["Fordham", Vector2(4100, -8100)]]:
		var r := _route_to(target[1])
		check(not r.is_empty(), "route to %s" % target[0])
		if not r.is_empty():
			var end := Vector2(r["points"][-1]) / 100.0
			check(end.distance_to(target[1]) < 400.0, "%s route ends nearby (%d m off)" % [target[0], end.distance_to(target[1])])


func test_every_bridge_carries_traffic() -> void:
	for br in world.bridge_paths:
		var path: PackedVector2Array = br["path"]
		var a := roads.locate(Vector2i(roundi(path[0].x * 100), roundi(path[0].y * 100)))
		var b := roads.locate(Vector2i(roundi(path[-1].x * 100), roundi(path[-1].y * 100)))
		var r := roads.route(a, b)
		check(not r.is_empty(), "%s: ends connected" % br["name"])
		var near_a := (Vector2(roads.location_point(a)) / 100.0).distance_to(path[0])
		var near_b := (Vector2(roads.location_point(b)) / 100.0).distance_to(path[-1])
		check(near_a < 5.0 and near_b < 5.0, "%s: road network reaches both ends (%.0f m, %.0f m)" % [br["name"], near_a, near_b])


func test_blocks_on_land_and_outside_little_italy() -> void:
	var bad := 0
	var li: Rect2 = world.regions[0]["rect"]
	for b in world.blocks:
		if not b.get("gen", false):
			continue
		for q in WorldLayout.block_corners(b):
			if not world.geo.is_land(q) or li.has_point(q):
				bad += 1
				break
	check_eq(bad, 0, "generated blocks sit on land, clear of Little Italy")
	var styles := {}
	for b in world.blocks:
		styles[b["style"]] = true
	check(styles.size() >= 15, "distinct neighbourhood styles (%d)" % styles.size())


func test_world_is_deterministic() -> void:
	var again := WorldLayout.build(content.worlds["nyc_1977"], content)
	check_eq(again.blocks.size(), world.blocks.size(), "same blocks")
	check_eq(again.graph_nodes.size(), world.graph_nodes.size(), "same nodes")
	check_eq(again.graph_edges.size(), world.graph_edges.size(), "same edges")
	var same := true
	for i in range(0, world.blocks.size(), 37):
		if again.blocks[i].get("seed") != world.blocks[i].get("seed") or again.blocks[i]["rect"] != world.blocks[i]["rect"]:
			same = false
	check(same, "identical block seeds and shapes")
	var b: Dictionary = world.blocks[world.blocks.size() / 2]
	var f1 := BlockFiller.fill(b, world.sidewalk, world.curb_height)
	var f2 := BlockFiller.fill(again.blocks[world.blocks.size() / 2], world.sidewalk, world.curb_height)
	check_eq(f1["lots"].size(), f2["lots"].size(), "generated lots repeat exactly")
	if not f1["lots"].is_empty():
		check_eq(f1["lots"][0]["id"], f2["lots"][0]["id"], "stable generated lot ids")


func test_streaming_builders() -> void:
	var root := Node3D.new()
	var t := Time.get_ticks_msec()
	var stats := GeoShellBuilder.build(world, root)
	var shell_ms := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	var ob := OverviewBuilder.build(world, root)
	var overview_ms := Time.get_ticks_msec() - t
	print("    shell %d road tiles in %d ms; overview %d instances / %d tiles in %d ms" % [stats["road_chunks"], shell_ms,
		ob.instance_count, ob.tiles, overview_ms])
	check(stats["road_chunks"] > 50, "road tiles cover the province")
	check(ob.instance_count > 10_000, "overview massing covers the province")
	check(ob.tiles < 400, "overview draw calls bounded (%d tiles)" % ob.tiles)
	var wb := world.chunk_of(Vector2(2350, -150))
	var detail := ChunkDetailBuilder.build(world, wb)
	print("    Williamsburg detail chunk %s: %d lots, %d tris" % [wb, detail["lots"], detail["tris"]])
	check(detail["lots"] > 20, "Brooklyn chunk generates buildings on demand")
	var mid := FarCityBuilder.build_arrays(world, wb, content.building_catalog)
	check(not mid.is_empty(), "mid-distance massing for Brooklyn")
	root.free()


## A v2 save from the first province, with one convoy crossing it and one on
## its way to a business, loads into the new map with nothing lost.
func test_v2_save_migrates_to_new_map() -> void:
	var old := WorldLayout.build(content.worlds["greater_new_york"], content)
	var w := SimBootstrap.new_world(content, old, "new_game", T0)
	w.execute({"type": "move_crew", "faction": "marino", "crew": "crew_mulberry", "point": [-1500_00, -1500_00]})
	w.execute({"type": "move_crew", "faction": "marino", "crew": "crew_bowery", "landmark": "lm_vesuvio"})
	w.advance_to(T0 + 20_000)
	var before: Dictionary = {}
	for cid in w.crews:
		before[cid] = (w.crews[cid] as CrewState).to_dict()
	var d: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	d["version"] = 2
	d.erase("world")
	var m := SimWorld.from_dict(d, content, roads, locs, SimBootstrap.legacy_roads(content), "nyc_1977")
	check(m != null, "v2 save loads")
	if m == null:
		return
	check_eq(m.world_id, "nyc_1977", "save now belongs to the new map")
	for cid in before:
		var c: CrewState = m.crews[cid]
		check_eq(c.soldiers, before[cid]["soldiers"], "%s keeps soldiers" % cid)
		check_eq(c.vehicle_id, before[cid]["vehicle"], "%s keeps vehicles" % cid)
		check_eq(c.hp, before[cid]["hp"], "%s keeps hp" % cid)
	var bowery: CrewState = m.crews["crew_bowery"]
	check(bowery.is_moving(), "travelling crew still on the road")
	check_eq(bowery.dest_landmark, "lm_vesuvio", "destination kept")
	check(bowery.route_serial > int(before["crew_bowery"]["route_serial"]), "route recalculated on the new map")
	var far: CrewState = m.crews["crew_mulberry"]
	check(far.is_moving() or far.status == "idle", "cross-province convoy rerouted or parked")
	m.advance_to(maxi(bowery.arrive_ms, far.arrive_ms) + 1000)
	check_eq(bowery.at_landmark, "lm_vesuvio", "arrives at its business")
	check(not far.is_moving(), "cross-province convoy arrives")
	var again: Dictionary = JSON.parse_string(JSON.stringify(m.to_dict()))
	check_eq(int(again["version"]), SimWorld.SAVE_VERSION, "re-saved as current version")
	check_eq(again["world"], "nyc_1977", "re-saved with world id")
