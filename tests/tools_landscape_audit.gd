extends SceneTree
## Actual blueprint + final routing + rendered field audit; writes reservations
## for future placement without creating gameplay state or square pads.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var start := Time.get_ticks_msec()
	var content := GameContent.load_default()
	var world := WorldLayout.build(content.worlds["nyc_1977"],content)
	var field := world.terrain
	var edge_counts := {}
	for e in world.graph_edges:
		var name: String = world.streets[e["street"]]["name"]
		edge_counts[name] = edge_counts.get(name,0)+1
	for net in content.worlds["nyc_1977"]["networks"]:
		var missing := []
		for road in net["roads"]:
			if not edge_counts.has(road["name"]):missing.append(road["name"])
		print("NETWORK ",net["id"]," missing: ",missing)
	var exported := []
	var by_region := {}
	var max_slope := 0.0
	var min_spacing := INF
	var bad_clearance := 0
	var bad_access := 0
	var driveway_conflicts := 0
	var wet_driveways := 0
	var graph := SimBootstrap.roads_for(world)
	for plot in field.plots:
		by_region[plot["region"]]=by_region.get(plot["region"],0)+1
		var p: Vector2=plot["center"]
		var elevation := field.height_at(p)
		for i in 32:
			var q := p+Vector2.from_angle(TAU*i/32.0)*TerrainField.EXCLUSION
			max_slope=maxf(max_slope,absf(field.height_at(q)-elevation)/TerrainField.EXCLUSION)
			if not field.is_dry(q):bad_clearance+=1
		var loc := graph.locate(Vector2i(roundi(plot["road_point"].x*100),roundi(plot["road_point"].y*100)))
		if (Vector2(graph.location_point(loc))/100.0).distance_to(plot["road_point"])>2.0:bad_access+=1
		for k in range(1,33):
			if not field.is_dry(plot["gate"].lerp(plot["road_point"],k/32.0)):wet_driveways+=1
		var entry: Dictionary = plot.duplicate()
		for key in ["center","gate","road_point"]:entry[key]=[plot[key].x,plot[key].y]
		exported.append(entry)
	# All pairs once, independently from the generator's spatial buckets.
	for i in field.plots.size():
		for j in range(i+1,field.plots.size()):
			var a: Dictionary=field.plots[i]
			var b: Dictionary=field.plots[j]
			min_spacing=minf(min_spacing,a["center"].distance_to(b["center"]))
			if a["center"].distance_to(b["center"])>800.0:continue
			if a["center"].distance_to(Geometry2D.get_closest_point_to_segment(a["center"],b["gate"],b["road_point"]))<118.0 \
					or b["center"].distance_to(Geometry2D.get_closest_point_to_segment(b["center"],a["gate"],a["road_point"]))<118.0:
				driveway_conflicts+=1
	var report := field.report.duplicate(true)
	report.merge({"regions":by_region,"minimum_spacing_m":min_spacing,"max_exclusion_disc_slope":max_slope,
		"water_violations":bad_clearance,"driveway_conflicts":driveway_conflicts,"wet_driveway_samples":wet_driveways,"road_access_violations":bad_access,"build_and_audit_ms":Time.get_ticks_msec()-start})
	var f := FileAccess.open("res://data/world/estate_reservations.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema":"estate-reservations-v1","world":"nyc_1977",
		"source_sha256":{"city":FileAccess.get_sha256("res://data/world/nyc_1977.json"),"landscape":FileAccess.get_sha256("res://data/world/landscape.json")},"report":report,"plots":exported}," "))
	print("LANDSCAPE_AUDIT ",JSON.stringify(report))
	quit(0 if bad_clearance==0 and bad_access==0 and driveway_conflicts==0 and wet_driveways==0 and min_spacing>=230.0 and max_slope<.01 else 1)
