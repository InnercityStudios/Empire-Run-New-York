extends SceneTree
## Dumps the generated geography world (blocks, roads, junctions, bridges,
## parks, nodes) to JSON for tools/geography/render_world.py.
## Usage: Godot --headless --path . -s tests/tools_geo_dump.gd -- <out.json>

func _initialize() -> void:
	var c := GameContent.load_default()
	var w := WorldLayout.build(c.worlds["nyc_1977"], c)
	var out := {"blocks": [], "segments": [], "junctions": [], "bridges": [], "nodes": [], "lots": [], "towers": []}
	for b in w.blocks:
		var q := WorldLayout.block_corners(b)
		out["blocks"].append({"style": b["style"], "poly": _arr(q)})
	for s in w.road_segments:
		out["segments"].append([s["from"].x, s["from"].y, s["to"].x, s["to"].y, s["width"]])
	for j in w.intersections:
		if j.has("poly"):
			out["junctions"].append(_arr(j["poly"]))
	for br in w.bridge_paths:
		out["bridges"].append({"name": br["name"], "path": _arr(br["path"]), "width": br["width"]})
	for p in w.graph_nodes:
		out["nodes"].append([p.x, p.y])
	for lot in w.lots:
		out["lots"].append([lot["transform"].origin.x, lot["transform"].origin.z])
	for t in w.towers:
		out["towers"].append([t["pos"].x, t["pos"].y, t["name"]])
	var args := OS.get_cmdline_user_args()
	var f := FileAccess.open(args[0] if not args.is_empty() else "user://geo_dump.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	quit()


func _arr(p: PackedVector2Array) -> Array:
	var a := []
	for q in p:
		a.append([snappedf(q.x, 0.1), snappedf(q.y, 0.1)])
	return a
