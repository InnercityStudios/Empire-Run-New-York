extends SceneTree
## Builds the geography world headless and prints layout statistics.
## Usage: Godot --headless --path . -s tests/tools_geo_stats.gd

func _initialize() -> void:
	var c := GameContent.load_default()
	var t := Time.get_ticks_msec()
	var w := WorldLayout.build(c.worlds["nyc_1977"], c)
	print("GEO build %d ms: blocks %d, lots %d, nodes %d, edges %d, segments %d, junctions %d, chunks %d, backdrop %d, park trees %d" % [
		Time.get_ticks_msec() - t, w.blocks.size(), w.lots.size(), w.graph_nodes.size(), w.graph_edges.size(),
		w.road_segments.size(), w.intersections.size(), w.chunk_keys().size(), w.backdrop_boxes.size(),
		w.park_areas.reduce(func(a, p): return a + p["trees"].size(), 0)])
	quit()
