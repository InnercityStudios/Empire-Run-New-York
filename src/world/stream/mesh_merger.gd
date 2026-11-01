class_name MeshMerger
extends RefCounted
## Merges transformed copies of cached asset surfaces into one array set per
## material without touching the RenderingServer, so it scales on worker
## threads. (SurfaceTool.append_from reads mesh data back from the
## RenderingServer, which serialised workers behind the render thread:
## measured 331 ms on the main thread vs up to 2.9 s per chunk on workers.)

var _acc: Dictionary = {}  ## material -> {v, n, t, uv, c, i}


func append(names: PackedStringArray, surfaces: Array, xform: Transform3D) -> void:
	var nbasis := xform.basis.inverse().transposed()
	var ntf := Transform3D(nbasis, Vector3.ZERO)
	var tbasis := xform.basis
	for s in surfaces.size():
		var arr: Array = surfaces[s]
		var mat: String = names[s] if s < names.size() else ""
		if not _acc.has(mat):
			_acc[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "t": PackedFloat32Array(),
				"uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
		var a: Dictionary = _acc[mat]
		# Packed arrays are values: work on typed locals and store them back.
		var v: PackedVector3Array = a["v"]
		var n: PackedVector3Array = a["n"]
		var uv: PackedVector2Array = a["uv"]
		var col: PackedColorArray = a["c"]
		var tan: PackedFloat32Array = a["t"]
		var idx: PackedInt32Array = a["i"]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var base := v.size()
		v.append_array(xform * verts)
		if arr[Mesh.ARRAY_NORMAL] != null:
			n.append_array(ntf * (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array))
		if arr[Mesh.ARRAY_TANGENT] != null:
			var src: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			var start := tan.size()
			tan.resize(start + src.size())
			for k in range(0, src.size(), 4):
				var tv := (tbasis * Vector3(src[k], src[k + 1], src[k + 2])).normalized()
				tan[start + k] = tv.x
				tan[start + k + 1] = tv.y
				tan[start + k + 2] = tv.z
				tan[start + k + 3] = src[k + 3]
		if arr[Mesh.ARRAY_TEX_UV] != null:
			uv.append_array(arr[Mesh.ARRAY_TEX_UV])
		if arr[Mesh.ARRAY_COLOR] != null:
			col.append_array(arr[Mesh.ARRAY_COLOR])
		else:
			var cs := col.size()
			col.resize(cs + verts.size())
			for k in range(cs, col.size()):
				col[k] = Color.WHITE
		var src_i: Variant = arr[Mesh.ARRAY_INDEX]
		var is0 := idx.size()
		if src_i == null:
			idx.resize(is0 + verts.size())
			for k in verts.size():
				idx[is0 + k] = base + k
		else:
			var si: PackedInt32Array = src_i
			idx.resize(is0 + si.size())
			for k in si.size():
				idx[is0 + k] = si[k] + base
		a["v"] = v
		a["n"] = n
		a["uv"] = uv
		a["c"] = col
		a["t"] = tan
		a["i"] = idx


## Array sets ready for ArrayMesh.add_surface_from_arrays: [[material, arrays]].
func result() -> Array:
	var out: Array = []
	for mat in _acc:
		var a: Dictionary = _acc[mat]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = a["v"]
		arrays[Mesh.ARRAY_NORMAL] = a["n"] if (a["n"] as PackedVector3Array).size() == (a["v"] as PackedVector3Array).size() else null
		arrays[Mesh.ARRAY_TANGENT] = a["t"] if (a["t"] as PackedFloat32Array).size() == (a["v"] as PackedVector3Array).size() * 4 else null
		arrays[Mesh.ARRAY_TEX_UV] = a["uv"] if (a["uv"] as PackedVector2Array).size() == (a["v"] as PackedVector3Array).size() else null
		arrays[Mesh.ARRAY_COLOR] = a["c"] if (a["c"] as PackedColorArray).size() == (a["v"] as PackedVector3Array).size() else null
		arrays[Mesh.ARRAY_INDEX] = a["i"]
		out.append([mat, arrays])
	return out
