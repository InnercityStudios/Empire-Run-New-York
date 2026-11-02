class_name LandscapeBlueprint
extends RefCounted
## Additive landscape layer. Original city/anchor definitions remain authored
## separately; no save coordinates, businesses or ownership are migrated.

static func apply(def: Dictionary, overlay: Dictionary) -> void:
	def["extent"] = overlay["extent"]
	# Union only extensions to the existing coastline. No raster tile land edges.
	for extension in overlay.get("landmasses", []):
		var remaining := GeoMap.poly(extension["polygon"])
		var merged := false
		for coast in def["landmasses"]:
			if coast["id"] != extension["join"]:
				continue
			var union := Geometry2D.merge_polygons(GeoMap.poly(coast["polygon"]), remaining)
			if union.size() == 1:
				var points := []
				for p in union[0]:
					points.append([p.x, p.y])
				coast["polygon"] = points
				merged = true
			break
		if not merged:
			def["landmasses"].append(extension)
	def["bridges"].append_array(overlay.get("bridges", []))
	def["networks"].append_array(overlay.get("networks", []))
	def["estate_regions"].append_array(overlay.get("estate_regions", []))
	def["landscape"] = overlay.get("settings", {})
