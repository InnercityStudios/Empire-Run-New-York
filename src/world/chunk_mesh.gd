class_name ChunkMesh
extends RefCounted
## Final assembly of merged world chunks: one surface per material, compressed
## vertex attributes and automatically generated LODs, so distant chunks drop
## small detail (window frames, fire-escape treads, dentils) on mobile GPUs.
## Used at runtime today and by the world bake step for prepared chunks.

const NORMAL_MERGE_ANGLE := 25.0
const NORMAL_SPLIT_ANGLE := 60.0


## `surfaces` is an Array of [material_name, SurfaceTool].
static func build(surfaces: Array, with_lods := true) -> ArrayMesh:
	var im := ImporterMesh.new()
	for entry in surfaces:
		var mat_name: String = entry[0]
		var st: SurfaceTool = entry[1]
		var arrays := st.commit_to_arrays()
		if arrays.is_empty() or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		var flags := 0 if QualityFlags.off("compress") else Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Materials.get_material(mat_name), mat_name, flags)
	if with_lods:
		im.generate_lods(NORMAL_MERGE_ANGLE, NORMAL_SPLIT_ANGLE, [])
	return im.get_mesh()


## Material names of a built chunk mesh, in surface order.
static func surface_names(mesh: ArrayMesh) -> PackedStringArray:
	var out := PackedStringArray()
	for i in mesh.get_surface_count():
		out.append(Materials.material_name_of(mesh.surface_get_material(i)))
	return out
