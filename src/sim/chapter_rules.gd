class_name ChapterRules
extends RefCounted
## Data-driven chapter requirements (data/chapters/chapters.json), evaluated
## from simulation state only, so the client display and the server's
## `claim_chapter` validation can never disagree.
##
## Objective types:
##   business_level {business, target}   own_business {business}
##   income {target $/h}                  businesses_owned {target}
##   collected_total {target $}           upgrades_total {target}
##   family_power {target}                soldiers {target}


static func objective_progress(world: SimWorld, fid: String, o: Dictionary) -> Dictionary:
	var cur := 0
	var target := int(o.get("target", 1))
	var landmark := ""
	var b: BusinessState = world.businesses.get(o.get("business", ""))
	match String(o.get("type", "")):
		"business_level":
			if b:
				cur = b.level if b.owner_id == fid else 0
				landmark = b.landmark_id
		"own_business":
			target = 1
			if b:
				cur = 1 if b.owner_id == fid else 0
				landmark = b.landmark_id
		"income":
			cur = world.faction_income_per_hour(fid)
		"businesses_owned":
			for x in world.businesses.values():
				if x.owner_id == fid:
					cur += 1
		"collected_total":
			cur = int(world.stats.get(fid, {}).get("collected", 0))
		"upgrades_total":
			cur = int(world.stats.get(fid, {}).get("upgrades", 0))
		"family_power":
			cur = world.faction_power(fid)
		"soldiers":
			for c in world.crews.values():
				if c.owner_id == fid:
					cur += PowerCalculator.soldier_count(c.soldiers)
	return {"current": cur, "target": target, "done": cur >= target, "landmark": landmark}


static func is_complete(world: SimWorld, fid: String, chapter: Dictionary) -> bool:
	for o in chapter.get("objectives", []):
		if not objective_progress(world, fid, o)["done"]:
			return false
	return true


## Unlock gate for a chapter beyond the first (previous complete + optional power).
static func unlocked(world: SimWorld, fid: String, chapter: Dictionary) -> bool:
	var need := int(chapter.get("unlock", {}).get("family_power", 0))
	return world.faction_power(fid) >= need


## "done" (reward claimed) | "ready" (complete, reward waiting) | "active" | "locked".
static func status(world: SimWorld, fid: String, index: int) -> String:
	if index < world.chapter_index:
		return "done"
	if index > world.chapter_index:
		return "locked"
	var ch: Dictionary = world.content.chapters[index]
	if not unlocked(world, fid, ch):
		return "locked"
	return "ready" if is_complete(world, fid, ch) else "active"
