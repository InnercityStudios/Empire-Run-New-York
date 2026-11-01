class_name ChunkDetailBuilder
extends RefCounted
## Builds the full-detail geometry of one world chunk: block pavements and
## lawns, buildings, street furniture and pier sheds merged into one mesh with
## one surface per material, plus instance lists for trees and parked cars.
##
## Runs on WorkerThreadPool threads. It only reads pre-warmed, immutable data
## (layout, cached asset meshes, shared materials), so it needs no locks.


static func build(world: WorldLayout, key: Vector2i) -> Dictionary:
	var c: Dictionary = world.chunk(key)
	var out := {"key": key, "surfaces": [], "trees": [], "parked": {}, "lots": 0, "tris": 0}
	if c.is_empty():
		return out
	var tools := {}
	for bi in c["blocks"]:
		var b: Dictionary = world.blocks[bi]
		if b["sidewalks"]:
			RoadBuilder.add_sidewalk(tools, b["rect"], world.curb_height, world.corner_radius, b["lawn"], world.sidewalk)
	var merger := MeshMerger.new()
	for li in c["lots"]:
		var lot: Dictionary = world.lots[li]
		_append(merger, AssetLibrary.building_mesh(lot["building"]), lot["transform"])
		out["lots"] += 1
	for p in c["props"]:
		_append(merger, AssetLibrary.prop_mesh(p["prop"]), p["transform"])
	for pr in c["piers"]:
		_append(merger, AssetLibrary.building_mesh("pier_shed_a"), pr["shed"])
	var surfaces: Array = merger.result()
	for mat_name in tools:
		var st: SurfaceTool = tools[mat_name]
		st.generate_tangents()
		surfaces.append([mat_name, st.commit_to_arrays()])
	for s in surfaces:
		out["tris"] += (s[1][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if s[1][Mesh.ARRAY_INDEX] != null \
			else (s[1][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	out["surfaces"] = surfaces
	# Park tree stands: deterministic rotation and scale per position.
	for p in c["trees"]:
		var h := hash(Vector2i(roundi(p.x * 10), roundi(p.y * 10)))
		var sc := 0.8 + float(h % 1000) / 2500.0
		var basis := Basis(Vector3.UP, float(h % 6283) / 1000.0).scaled(Vector3(sc, sc, sc))
		out["trees"].append(Transform3D(basis, Vector3(p.x, 0.0, p.y)))
	out["parked"] = c["parking"]
	return out


## Uploads built surfaces (main thread): one surface per material.
static func to_mesh(surfaces: Array) -> Dictionary:
	var mesh := ArrayMesh.new()
	var names := PackedStringArray()
	var flags := 0 if QualityFlags.off("compress") else Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
	for s in surfaces:
		var arrays: Array = s[1]
		if arrays.is_empty() or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Materials.get_material(s[0]))
		names.append(s[0])
	return {"mesh": mesh if mesh.get_surface_count() > 0 else null, "names": names}


static func _append(merger: MeshMerger, mesh: ArrayMesh, xform: Transform3D) -> void:
	if mesh == null:
		return
	merger.append(AssetLibrary.surface_names(mesh), AssetLibrary.surface_arrays(mesh), xform)
