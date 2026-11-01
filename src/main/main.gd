extends Node
## Game entry point: builds the district, starts the session, wires the views.

@onready var world: CityWorld = $CityWorld
@onready var camera: StrategyCamera = $StrategyCamera
@onready var atmosphere: WorldAtmosphere = $Atmosphere


func _ready() -> void:
	add_to_group("main")
	var district: Dictionary = Content.db.districts["little_italy"]
	var layout := DistrictLayout.build(district, Content.db.building_catalog)
	world.build(layout)
	camera.set_bounds(layout.bounds.grow(-40.0))
	camera.distance_changed.connect(atmosphere.on_camera_distance)
	camera.focus_on(Vector3(-80, 0, 0), 150.0, true)


func dev_select(_id: String) -> void:
	pass
