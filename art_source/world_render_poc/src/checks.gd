extends SceneTree
## Adversarial topology check: a water hole wholly inside a coarse cell.
func _initialize() -> void:
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/geography.json"))["regions"][0].duplicate(true)
	source["bounds"]=[0,0,32,32]
	source["land"]=[[0,0],[32,0],[32,32],[0,32]]
	source["waters"]=[{"id":"tiny_hole","polygon":[[12,12],[12.5,12],[12.5,12.5],[12,12.5]]}]
	source["roads"]=[];source["nodes"]={}
	source["terrain"]["fields"]=[];source["terrain"]["hills"]=[]
	var g := ProofGeography.load_region(source)
	var ground := ConformingMesh.build(g,"ground",Rect2(0,0,32,32),32)
	var water := ConformingMesh.build(g,"water",Rect2(0,0,32,32),32)
	var valid: bool=ground["errors"].is_empty() and absf(float(ground["area"])-1023.75)<.002 and absf(float(water["area"])-.25)<.002
	print("TINY_HOLE_CHECK ",JSON.stringify({"pass":valid,"ground_area_m2":ground["area"],"water_area_m2":water["area"],"errors":ground["errors"]}))
	quit(0 if valid else 1)
