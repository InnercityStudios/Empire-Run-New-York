extends TestCase
## District layout and road network invariants.

var content: GameContent
var layout: DistrictLayout


func before_each() -> void:
	if content == null:
		content = GameContent.load_default()
		layout = DistrictLayout.build(content.districts["little_italy"], content.building_catalog)


func test_grid_dimensions() -> void:
	check_eq(layout.intersections.size(), layout.avenues.size() * layout.streets.size(), "intersection count")
	check_eq(layout.blocks.size(), (layout.avenues.size() + 1) * (layout.streets.size() + 1), "block count")


func test_all_landmarks_placed() -> void:
	for lm in content.districts["little_italy"]["landmarks"]:
		check(layout.landmarks.has(lm["id"]), "landmark %s placed" % lm["id"])


func test_buildings_stay_off_the_road() -> void:
	for lot in layout.lots:
		var t: Transform3D = lot["transform"]
		var b: Dictionary = content.building_catalog[lot["building"]]
		var hw: float = b["width"] * 0.5 * t.basis.x.length()
		for corner in [Vector3(-hw, 0, 0), Vector3(hw, 0, 0)]:
			var local: Vector3 = corner / Vector3(t.basis.x.length(), 1, 1)
			var p: Vector3 = t * local
			for seg in layout.road_segments:
				var a: Vector2 = seg["from"]
				var e: Vector2 = seg["to"]
				var r := Rect2(a, Vector2.ZERO).expand(e).grow(seg["width"] * 0.5 - 0.05)
				check(not r.has_point(Vector2(p.x, p.z)), "%s front corner on road %s" % [lot["building"], seg["street"]])


func test_lots_do_not_overlap_along_faces() -> void:
	var fronts := {}
	for lot in layout.lots:
		var t: Transform3D = lot["transform"]
		var key := "%d|%.2f|%.2f" % [lot["block"], t.basis.z.x, t.basis.z.z]
		fronts[key] = fronts.get(key, []) + [lot]
	for key in fronts:
		var spans := []
		for lot in fronts[key]:
			var t: Transform3D = lot["transform"]
			var dir := t.basis.x.normalized()
			var w: float = content.building_catalog[lot["building"]]["width"] * t.basis.x.length()
			var c := t.origin.dot(dir)
			spans.append([c - w * 0.5, c + w * 0.5])
		spans.sort_custom(func(a, b): return a[0] < b[0])
		for i in spans.size() - 1:
			check(spans[i][1] <= spans[i + 1][0] + 0.05, "overlap on face %s" % key)


func test_road_graph_connected() -> void:
	var roads := SimBootstrap.roads_for(layout)
	var seen := {0: true}
	var stack := [0]
	while not stack.is_empty():
		var n: int = stack.pop_back()
		for adj in roads.neighbours(n):
			if not seen.has(adj[1]):
				seen[adj[1]] = true
				stack.append(adj[1])
	check_eq(seen.size(), roads.nodes.size(), "every node reachable")


func test_landmarks_front_onto_roads() -> void:
	var roads := SimBootstrap.roads_for(layout)
	var locs := SimBootstrap.landmark_locations(layout, roads)
	for id in locs:
		var p := Vector2(roads.location_point(locs[id])) / 100.0
		var f: Vector2 = layout.landmarks[id]["frontage"]
		check(p.distance_to(f) < 0.5, "%s frontage lies on its street" % id)


func test_layout_is_deterministic() -> void:
	var again := DistrictLayout.build(content.districts["little_italy"], content.building_catalog)
	check_eq(again.lots.size(), layout.lots.size(), "same lot count")
	var same := true
	for i in layout.lots.size():
		if layout.lots[i]["building"] != again.lots[i]["building"]:
			same = false
	check(same, "same building choices")


## Golden fingerprint recorded before the world refactor (tests/tools_fingerprint.gd).
const LITTLE_ITALY_FINGERPRINT := "381:708f77ce754b9eda"


func test_little_italy_layout_preserved() -> void:
	check_eq(LayoutFingerprint.of(layout), LITTLE_ITALY_FINGERPRINT, "Little Italy lots unchanged")


func test_lot_ids_unique_and_stable() -> void:
	var seen := {}
	for lot in layout.lots:
		check(not seen.has(lot["id"]), "unique lot id %s" % lot["id"])
		seen[lot["id"]] = true
	check_eq(layout.lots[0]["id"], "little_italy:0", "ids are district-scoped")
