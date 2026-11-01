extends TestCase
## Greater New York world layout: connectivity, preservation, determinism.

static var content: GameContent
static var world: WorldLayout
static var build_ms := 0


func before_each() -> void:
	if world == null:
		content = GameContent.load_default()
		var t := Time.get_ticks_msec()
		world = WorldLayout.build(content.worlds["greater_new_york"], content)
		build_ms = Time.get_ticks_msec() - t
		print("    world: %d regions, %d lots, %d props, %d nodes, %d edges, %d chunks, %d park trees in %d ms" % [
			world.regions.size(), world.lots.size(), world.props.size(), world.graph_nodes.size(),
			world.graph_edges.size(), world.chunk_keys().size(), world.parks[0]["trees"].size(), build_ms])


func test_little_italy_preserved_inside_world() -> void:
	var li: DistrictLayout = world.regions[0]["layout"]
	check_eq(world.regions[0]["id"], "little_italy", "Little Italy is the first region")
	check_eq(LayoutFingerprint.of(li), "381:708f77ce754b9eda", "Little Italy lots unchanged in the world")
	for lm in content.districts["little_italy"]["landmarks"]:
		check(world.landmarks.has(lm["id"]), "landmark %s present" % lm["id"])


func test_road_network_fully_connected() -> void:
	var roads := SimBootstrap.roads_for(world)
	var seen := {0: true}
	var stack := [0]
	while not stack.is_empty():
		var n: int = stack.pop_back()
		for adj in roads.neighbours(n):
			if not seen.has(adj[1]):
				seen[adj[1]] = true
				stack.append(adj[1])
	check_eq(seen.size(), roads.nodes.size(), "every road node reachable from Little Italy")


func test_cross_world_route_uses_arterials() -> void:
	var roads := SimBootstrap.roads_for(world)
	var locs := SimBootstrap.landmark_locations(world, roads)
	var far := roads.locate(Vector2i(-1600_00, -1600_00))  # Spuyten Heights
	var t := Time.get_ticks_msec()
	var r := roads.route(locs["lm_hq_marino"], far)
	var ms := Time.get_ticks_msec() - t
	check(not r.is_empty(), "route found across the world")
	check(r["length"] > 2000_00, "meaningful distance (>2 km)")
	check(r["cost"] < r["length"], "faster than base speed thanks to arterials")
	check(ms < 400, "routing time %d ms" % ms)


func test_bridge_reaches_future_city_portal() -> void:
	check_eq(world.portals.size(), 1, "one future-city portal")
	var roads := SimBootstrap.roads_for(world)
	var portal: Vector2 = world.graph_nodes[world.portals[0]["node"]]
	var dest := roads.locate(Vector2i(roundi(portal.x * 100), roundi(portal.y * 100)))
	var locs := SimBootstrap.landmark_locations(world, roads)
	check(not roads.route(locs["lm_hq_marino"], dest).is_empty(), "portal reachable by road")


func test_open_spaces_exist() -> void:
	check(world.parks.size() >= 1 and world.parks[0]["trees"].size() > 500, "large wooded park")
	check(world.piers.size() >= 10, "working piers (%d)" % world.piers.size())
	var styles := {}
	for r in world.regions:
		styles[r["style"]] = true
	for s in ["tenement", "industrial", "rowhouse", "suburban", "towers", "waterfront", "park"]:
		check(styles.has(s), "has %s neighbourhood" % s)


func test_world_is_deterministic() -> void:
	var again := WorldLayout.build(content.worlds["greater_new_york"], content)
	check_eq(again.lots.size(), world.lots.size(), "same lot count")
	check_eq(again.graph_nodes.size(), world.graph_nodes.size(), "same node count")
	var same := true
	for i in world.lots.size():
		if world.lots[i]["id"] != again.lots[i]["id"] or world.lots[i]["building"] != again.lots[i]["building"]:
			same = false
			break
	check(same, "identical lots and identities")


func test_every_lot_in_a_chunk() -> void:
	var counted := 0
	for k in world.chunk_keys():
		counted += world.chunk(k)["lots"].size()
	check_eq(counted, world.lots.size() - world.landmarks.size(), "chunks cover every generic lot")
