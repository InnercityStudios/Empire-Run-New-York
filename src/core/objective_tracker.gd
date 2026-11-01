class_name ObjectiveTracker
extends RefCounted
## Chapter objectives (data/scenarios/*.json "objectives"), evaluated from the
## live simulation state. Nothing is stored: progress is always what the
## world currently shows, so it can never disagree with the game.
##
## Types: business_level {business, target}, own_business {business},
## income {target: dollars per hour}.


## The first unfinished objective: {id, text, current, target, landmark} or {}.
static func current(world: SimWorld, defs: Array) -> Dictionary:
	for d in defs:
		var o := evaluate(world, d)
		if o["current"] < o["target"]:
			return o
	return {}


static func evaluate(world: SimWorld, d: Dictionary) -> Dictionary:
	var out := {"id": d.get("id", ""), "text": d.get("text", ""), "current": 0, "target": int(d.get("target", 1)),
		"landmark": ""}
	var b: BusinessState = world.businesses.get(d.get("business", ""))
	match String(d.get("type", "")):
		"business_level":
			if b:
				out["current"] = b.level if b.owner_id == world.player_faction_id else 0
				out["landmark"] = b.landmark_id
		"own_business":
			if b:
				out["current"] = 1 if b.owner_id == world.player_faction_id else 0
				out["landmark"] = b.landmark_id
		"income":
			out["current"] = world.faction_income_per_hour(world.player_faction_id)
	return out
