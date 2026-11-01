class_name SimBootstrap
extends RefCounted
## Builds the simulation's static inputs (road graph, landmark locations) from
## a layout. Shared by the client session, tests and future servers.
## A layout is any object with `graph_nodes`, `graph_edges` and `landmarks`
## (DistrictLayout for a single neighbourhood, WorldLayout for a province).


static func roads_for(layout: RefCounted) -> RoadGraph:
	return RoadGraph.from_layout(layout.get("graph_nodes"), layout.get("graph_edges"))


static func landmark_locations(layout: RefCounted, roads: RoadGraph) -> Dictionary:
	var out := {}
	var landmarks: Dictionary = layout.get("landmarks")
	for id in landmarks:
		var f: Vector2 = landmarks[id]["frontage"]
		out[id] = roads.locate(Vector2i(roundi(f.x * 100.0), roundi(f.y * 100.0)))
	return out


static func new_world(content: GameContent, layout: RefCounted, scenario_id: String, start_ms: int) -> SimWorld:
	var roads := roads_for(layout)
	return SimWorld.create_new(content, roads, landmark_locations(layout, roads), content.scenarios[scenario_id], start_ms)


## The Little Italy-only graph that v1 saves were written against.
static func legacy_roads(content: GameContent) -> RoadGraph:
	var l := DistrictLayout.build(content.districts["little_italy"], content.building_catalog)
	return roads_for(l)
