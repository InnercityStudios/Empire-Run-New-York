class_name PolygonBlockFiller
extends RefCounted
## Frontages derived from bounded street faces, including irregular blocks.
## Models retain their authored facade-at-z=0 convention. Full footprint
## containment and polygon collision prevent rows intersecting at corners.

static func fill(block: Dictionary, sidewalk: float, curb_h: float, with_props: bool) -> Dictionary:
	var result := {"lots":[],"props":[],"parking":[]}
	var poly: PackedVector2Array = block["polygon"]
	var kit: Dictionary = block["kit"]
	var rules: Dictionary = kit["fill"]
	var rng := RandomNumberGenerator.new()
	rng.seed=int(block["seed"])
	var occupied: Array = []
	var index := 0
	var area := StreetNetwork._signed_area(poly)
	for edge in poly.size():
		var a := poly[edge]
		var b := poly[(edge+1)%poly.size()]
		var length := a.distance_to(b)
		var right := (b-a).normalized()
		var inward := Vector2(-right.y,right.x) * (1.0 if area>0.0 else -1.0)
		var out := -inward
		var u := sidewalk+3.0
		while u < length-sidewalk-6.0:
			var fits: Array = kit["ids"].filter(func(id):return float(kit["dims"][id].x)<length-u-sidewalk)
			if fits.is_empty():break
			var id: String = fits[rng.randi()%fits.size()]
			var dim: Vector3 = kit["dims"][id]
			var origin := a+right*(u+dim.x*.5)+inward*(sidewalk+float(rules.get("setback",0.0)))
			var hw := dim.x*.5
			var footprint := PackedVector2Array([origin-right*hw,origin+right*hw,
				origin+right*hw+inward*dim.z,origin-right*hw+inward*dim.z])
			var valid := true
			for p in footprint:
				if not Geometry2D.is_point_in_polygon(p,poly):valid=false;break
			if valid:
				for previous in occupied:
					if not Geometry2D.intersect_polygons(previous,footprint).is_empty():valid=false;break
			if valid:
				var model_right := Vector2(out.y,-out.x)
				var t := Transform3D(Basis(Vector3(model_right.x,0,model_right.y),Vector3.UP,Vector3(out.x,0,out.y)),Vector3(origin.x,curb_h,origin.y))
				result["lots"].append({"id":"%s:%d:%d"%[block["district"],block["index"],index],"building":id,"transform":t})
				occupied.append(footprint)
			index+=1
			var gap: Array = rules.get("gap",[0,0])
			u+=dim.x+rng.randf_range(float(gap[0]),float(gap[1]))+0.4
		if with_props:
			var lamp := 9.0
			while lamp < length-9.0:
				var p := a+right*lamp+inward*1.0
				result["props"].append({"prop":"street_lamp","transform":Transform3D(Basis(),Vector3(p.x,curb_h,p.y))})
				if rng.randf()<float(rules.get("trees",0.4)):
					p+=right*7.0+inward*.7
					result["props"].append({"prop":"tree_a","transform":Transform3D(Basis(Vector3.UP,rng.randf()*TAU),Vector3(p.x,curb_h,p.y))})
				lamp+=32.0
	return result
