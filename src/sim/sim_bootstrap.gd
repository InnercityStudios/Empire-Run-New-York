class_name SimBootstrap
extends RefCounted
## Builds the simulation's static inputs (road graph, landmark locations) from
## a district layout. Shared by the client session, tests and future servers.


static func roads_for(layout: DistrictLayout) -> RoadGraph:
	return RoadGraph.from_layout(layout.graph_nodes, layout.graph_edges)


static func landmark_locations(layout: DistrictLayout, roads: RoadGraph) -> Dictionary:
	var out := {}
	for id in layout.landmarks:
		var f: Vector2 = layout.landmarks[id]["frontage"]
		out[id] = roads.locate(Vector2i(roundi(f.x * 100.0), roundi(f.y * 100.0)))
	return out


static func new_world(content: GameContent, layout: DistrictLayout, scenario_id: String, start_ms: int) -> SimWorld:
	var roads := roads_for(layout)
	return SimWorld.create_new(content, roads, landmark_locations(layout, roads), content.scenarios[scenario_id], start_ms)
