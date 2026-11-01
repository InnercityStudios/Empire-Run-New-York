class_name FactionState
extends RefCounted
## A family (player or AI) or the neutral owner of unclaimed businesses.

var id := ""
var name := ""
var boss := ""
var color := "#ffffff"
var cash := 0
var is_player := false
var ai := false


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "boss": boss, "color": color, "cash": cash, "is_player": is_player, "ai": ai}


static func from_dict(d: Dictionary) -> FactionState:
	var f := FactionState.new()
	f.id = d["id"]
	f.name = d.get("name", "")
	f.boss = d.get("boss", "")
	f.color = d.get("color", "#ffffff")
	f.cash = int(d.get("cash", 0))
	f.is_player = bool(d.get("is_player", false))
	f.ai = bool(d.get("ai", false))
	return f
