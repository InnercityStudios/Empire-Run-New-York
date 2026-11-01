extends SceneTree
func _initialize() -> void:
	var c := GameContent.load_default()
	var w := WorldLayout.build(c.worlds["greater_new_york"], c)
	for r in w.regions:
		var dl: DistrictLayout = r["layout"]
		var rect: Rect2 = r["rect"]
		print("%-22s %-10s lots=%5d props=%5d area=%.2f km2 density=%4d/km2" % [r["id"], r["style"], dl.lots.size(), dl.props.size(), rect.get_area() / 1e6, dl.lots.size() / maxf(rect.get_area() / 1e6, 0.001)])
	quit()
