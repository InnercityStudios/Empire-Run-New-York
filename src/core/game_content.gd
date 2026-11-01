class_name GameContent
extends RefCounted
## Immutable game content loaded from data/ JSON files.
##
## Both presentation and simulation read definitions from here; the simulation
## never touches files or nodes, so the same content can be loaded by a
## headless server build.

const DATA_ROOT := "res://data/"

var business_types: Dictionary = {}
var soldier_tiers: Dictionary = {}
var vehicles: Dictionary = {}
var traffic_paints: Array = []
var rarities: Dictionary = {}
var characters: Dictionary = {}
var abilities: Dictionary = {}
var headquarters: Dictionary = {}
var building_catalog: Dictionary = {}
var districts: Dictionary = {}
var scenarios: Dictionary = {}
var errors: PackedStringArray = []


static func load_default() -> GameContent:
	var c := GameContent.new()
	c.load_all(DATA_ROOT)
	return c


func load_all(root: String) -> void:
	var biz: Dictionary = _read(root + "defs/businesses.json")
	business_types = biz.get("business_types", {})
	var units: Dictionary = _read(root + "defs/units.json")
	soldier_tiers = units.get("soldier_tiers", {})
	vehicles = units.get("vehicles", {})
	traffic_paints = units.get("traffic_paints", [])
	var chars: Dictionary = _read(root + "defs/characters.json")
	rarities = chars.get("rarities", {})
	characters = chars.get("capos", {})
	abilities = chars.get("abilities", {})
	headquarters = _read(root + "defs/headquarters.json")
	for b in _read(root + "building_catalog.json").get("buildings", []):
		building_catalog[b["id"]] = b
	districts["little_italy"] = _read(root + "districts/little_italy.json")
	scenarios["new_game"] = _read(root + "scenarios/new_game.json")
	_validate()
	for e in errors:
		push_error("Content: " + e)


func business_type(type_id: String) -> Dictionary:
	return business_types.get(type_id, {})


func business_level(type_id: String, level: int) -> Dictionary:
	var levels: Array = business_type(type_id).get("levels", [])
	if levels.is_empty():
		return {}
	return levels[clampi(level, 1, levels.size()) - 1]


func business_max_level(type_id: String) -> int:
	return business_type(type_id).get("levels", []).size()


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("missing file %s" % path)
		return {}
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		errors.append("%s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("%s: root must be an object" % path)
		return {}
	return json.data


func _validate() -> void:
	for type_id in business_types:
		var levels: Array = business_types[type_id].get("levels", [])
		if levels.is_empty():
			errors.append("business type %s has no levels" % type_id)
	var scenario: Dictionary = scenarios.get("new_game", {})
	for b in scenario.get("businesses", []):
		if not business_types.has(b.get("type", "")):
			errors.append("scenario business %s has unknown type %s" % [b.get("id"), b.get("type")])
	for c in scenario.get("crews", []):
		if not characters.has(c.get("capo", "")):
			errors.append("crew %s has unknown capo %s" % [c.get("id"), c.get("capo")])
		if not vehicles.has(c.get("vehicle", "")):
			errors.append("crew %s has unknown vehicle %s" % [c.get("id"), c.get("vehicle")])
		for tier in c.get("soldiers", {}):
			if not soldier_tiers.has(tier):
				errors.append("crew %s has unknown soldier tier %s" % [c.get("id"), tier])
	for d in districts.values():
		for lm in d.get("landmarks", []):
			if not building_catalog.has(lm.get("building", "")):
				errors.append("landmark %s uses unknown building %s" % [lm.get("id"), lm.get("building")])
