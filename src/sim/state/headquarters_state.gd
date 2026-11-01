class_name HeadquartersState
extends RefCounted
## A family's headquarters. Facility levels drive capacities; the separate
## HQ management view (next milestone) edits this same state via commands.

var faction_id := ""
var landmark_id := ""
var name := ""
var level := 1
var facilities: Dictionary = {}  ## facility id -> level


func level_def(content: GameContent) -> Dictionary:
	var levels: Array = content.headquarters.get("levels", [])
	if levels.is_empty():
		return {}
	return levels[clampi(level, 1, levels.size()) - 1]


func to_dict() -> Dictionary:
	return {"faction": faction_id, "landmark": landmark_id, "name": name, "level": level,
		"facilities": facilities.duplicate()}


static func from_dict(d: Dictionary) -> HeadquartersState:
	var h := HeadquartersState.new()
	h.faction_id = d["faction"]
	h.landmark_id = d.get("landmark", "")
	h.name = d.get("name", "")
	h.level = int(d.get("level", 1))
	for k in d.get("facilities", {}):
		h.facilities[k] = int(d["facilities"][k])
	return h
