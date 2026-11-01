class_name SimWorld
extends RefCounted
## Authoritative game simulation for one district/server shard.
##
## - Pure logic: no nodes, files or rendering. Content and the road graph are
##   injected, so a headless server can run the same code.
## - Integer state (dollars, cm, ms) and a seeded RNG make it reproducible.
## - All change goes through `execute(command)`; clients send the same command
##   dictionaries a server would validate.
## - Time-driven: `advance_to(t)` processes due timers (arrivals, upgrades, AI)
##   in timestamp order, so results never depend on frame rate.
## - Changes are reported as event dictionaries collected via `drain_events()`.

const SAVE_VERSION := 2
## v1 stored road locations as edge indices of the Little Italy-only graph.
const LEGACY_SAVE_VERSION := 1
const NEUTRAL_FACTION := "independent"
const AI_INTERVAL_MS := 12_000
const PURCHASE_LEVEL_STEP_PERMILLE := 500

var content: GameContent
var roads: RoadGraph
var landmark_locations: Dictionary = {}  ## landmark id -> road location
var now_ms := 0
var rng: SimRng
var player_faction_id := ""
var factions: Dictionary = {}
var businesses: Dictionary = {}
var crews: Dictionary = {}
var headquarters: Dictionary = {}       ## faction id -> HeadquartersState
var ai_next_ms := 0
var _events: Array = []


static func create_new(p_content: GameContent, p_roads: RoadGraph, locations: Dictionary, scenario: Dictionary,
		start_ms: int) -> SimWorld:
	var w := SimWorld.new()
	w.content = p_content
	w.roads = p_roads
	w.landmark_locations = locations
	w.now_ms = start_ms
	w.rng = SimRng.new(int(scenario.get("seed", 1)))
	w.player_faction_id = scenario.get("player_faction", "")
	w.ai_next_ms = start_ms + AI_INTERVAL_MS
	for f in scenario.get("factions", []):
		var fs := FactionState.from_dict(f)
		w.factions[fs.id] = fs
	for h in scenario.get("headquarters", []):
		var hs := HeadquartersState.from_dict(h)
		w.headquarters[hs.faction_id] = hs
	for b in scenario.get("businesses", []):
		var bs := BusinessState.new()
		bs.id = b["id"]
		bs.type_id = b["type"]
		bs.name = b.get("name", bs.id)
		bs.landmark_id = b.get("landmark", "")
		bs.owner_id = b.get("owner", NEUTRAL_FACTION)
		bs.level = int(b.get("level", 1))
		bs.territory = scenario.get("district", "")
		# Give starting businesses some uncollected income.
		var pre_ms := int(float(b.get("stored_hours", 0.0)) * BusinessState.MS_PER_HOUR)
		bs.last_accrual_ms = start_ms - pre_ms
		w.businesses[bs.id] = bs
	for c in scenario.get("crews", []):
		var cs := CrewState.new()
		cs.id = c["id"]
		cs.owner_id = c["owner"]
		cs.name = c.get("name", cs.id)
		cs.capo_id = c.get("capo", "")
		for tier in c.get("soldiers", {}):
			cs.soldiers[tier] = int(c["soldiers"][tier])
		cs.vehicle_id = c.get("vehicle", "")
		cs.vehicle_count = int(c.get("vehicles", 1))
		cs.max_hp = PowerCalculator.crew_max_hp(cs.soldiers, p_content)
		cs.hp = cs.max_hp
		cs.at_landmark = c.get("start_landmark", "")
		cs.location = w.landmark_locations.get(cs.at_landmark, {"edge": 0, "offset": 0}).duplicate()
		w.crews[cs.id] = cs
		w._station_if_possible(cs)
	return w


# --- Queries -----------------------------------------------------------------------
func faction(id: String) -> FactionState:
	return factions.get(id)


func player() -> FactionState:
	return factions.get(player_faction_id)


func business_at_landmark(landmark_id: String) -> BusinessState:
	for b in businesses.values():
		if b.landmark_id == landmark_id:
			return b
	return null


func hq_at_landmark(landmark_id: String) -> HeadquartersState:
	for h in headquarters.values():
		if h.landmark_id == landmark_id:
			return h
	return null


func crew_power(crew_id: String) -> int:
	return PowerCalculator.crew_power(crews[crew_id], content) if crews.has(crew_id) else 0


func faction_power(faction_id: String) -> int:
	var total := 0
	for c in crews.values():
		if c.owner_id == faction_id:
			total += PowerCalculator.crew_power(c, content)
	return total


func faction_income_per_hour(faction_id: String) -> int:
	var total := 0
	for b in businesses.values():
		if b.owner_id == faction_id:
			total += b.net_per_hour(content)
	return total


func purchase_price(b: BusinessState) -> int:
	var base := int(content.business_type(b.type_id).get("purchase_price", 0))
	return base * (1000 + PURCHASE_LEVEL_STEP_PERMILLE * (b.level - 1)) / 1000


## "shielded", "guarded" (crew stationed) or "exposed".
func vulnerability(b: BusinessState) -> String:
	if b.shield_until_ms > now_ms:
		return "shielded"
	if b.assigned_crew_id != "":
		return "guarded"
	return "exposed"


func drain_events() -> Array:
	var e := _events
	_events = []
	return e


# --- Time ----------------------------------------------------------------------------
func advance_to(t: int) -> void:
	# After long offline periods only replay the last few AI decisions;
	# income is timestamp-based and needs no catch-up.
	if ai_next_ms < t - AI_INTERVAL_MS * 8:
		ai_next_ms = t - AI_INTERVAL_MS * 8
	var guard := 0
	while guard < 10_000:
		guard += 1
		var due := _next_due()
		if due.is_empty() or due["t"] > t:
			break
		now_ms = maxi(now_ms, due["t"])
		match due["kind"]:
			"arrive":
				_arrive(crews[due["id"]])
			"upgrade":
				_finish_upgrade(businesses[due["id"]])
			"ai":
				_ai_tick()
				ai_next_ms = now_ms + AI_INTERVAL_MS
	now_ms = maxi(now_ms, t)


func _next_due() -> Dictionary:
	var best := {}
	var consider := func(time: int, kind: String, id: String) -> void:
		if best.is_empty() or time < best["t"] or (time == best["t"] and kind + id < best["kind"] + best["id"]):
			best.clear()
			best.merge({"t": time, "kind": kind, "id": id})
	for c in crews.values():
		if c.is_moving():
			consider.call(c.arrive_ms, "arrive", c.id)
	for b in businesses.values():
		if b.upgrade_finish_ms > 0:
			consider.call(b.upgrade_finish_ms, "upgrade", b.id)
	consider.call(ai_next_ms, "ai", "")
	return best


# --- Commands --------------------------------------------------------------------------
## Validates and applies a command. Returns {ok: bool, error?: String, ...}.
func execute(cmd: Dictionary) -> Dictionary:
	var fid: String = cmd.get("faction", "")
	if not factions.has(fid):
		return _fail("unknown_faction")
	match cmd.get("type", ""):
		"collect_business":
			return _cmd_collect(fid, cmd.get("business", ""))
		"collect_all":
			return _cmd_collect_all(fid)
		"upgrade_business":
			return _cmd_upgrade(fid, cmd.get("business", ""))
		"acquire_business":
			return _cmd_acquire(fid, cmd.get("business", ""))
		"move_crew":
			return _cmd_move(fid, cmd.get("crew", ""), cmd)
		"recall_crew":
			var hq: HeadquartersState = headquarters.get(fid)
			if hq == null:
				return _fail("no_headquarters")
			return _cmd_move(fid, cmd.get("crew", ""), {"landmark": hq.landmark_id})
	return _fail("unknown_command")


func _fail(code: String) -> Dictionary:
	return {"ok": false, "error": code}


func _owned_business(fid: String, bid: String) -> BusinessState:
	var b: BusinessState = businesses.get(bid)
	return b if b != null and b.owner_id == fid else null


func _cmd_collect(fid: String, bid: String) -> Dictionary:
	var b := _owned_business(fid, bid)
	if b == null:
		return _fail("not_owner")
	var amount := b.stored(now_ms, content)
	if amount <= 0:
		return _fail("nothing_to_collect")
	_collect(b, amount)
	return {"ok": true, "amount": amount}


func _cmd_collect_all(fid: String) -> Dictionary:
	var total := 0
	var ids := businesses.keys()
	ids.sort()
	for bid in ids:
		var b: BusinessState = businesses[bid]
		if b.owner_id != fid:
			continue
		var amount := b.stored(now_ms, content)
		if amount > 0:
			_collect(b, amount)
			total += amount
	if total <= 0:
		return _fail("nothing_to_collect")
	return {"ok": true, "amount": total}


func _collect(b: BusinessState, amount: int) -> void:
	var f: FactionState = factions[b.owner_id]
	f.cash += amount
	b.banked = 0
	b.last_accrual_ms = now_ms
	_emit("business_collected", {"business": b.id, "faction": f.id, "amount": amount})
	_emit("cash_changed", {"faction": f.id, "cash": f.cash})


func _cmd_upgrade(fid: String, bid: String) -> Dictionary:
	var b := _owned_business(fid, bid)
	if b == null:
		return _fail("not_owner")
	if b.is_upgrading(now_ms):
		return _fail("already_upgrading")
	if b.level >= content.business_max_level(b.type_id):
		return _fail("max_level")
	var lvl := b.level_def(content)
	var cost := int(lvl.get("upgrade_cost", 0))
	var f: FactionState = factions[fid]
	if f.cash < cost:
		return _fail("insufficient_cash")
	f.cash -= cost
	b.upgrade_finish_ms = now_ms + int(lvl.get("upgrade_seconds", 0)) * 1000
	_emit("cash_changed", {"faction": fid, "cash": f.cash})
	_emit("upgrade_started", {"business": b.id, "finish_ms": b.upgrade_finish_ms})
	if b.upgrade_finish_ms <= now_ms:
		_finish_upgrade(b)
	return {"ok": true, "cost": cost, "finish_ms": b.upgrade_finish_ms}


func _finish_upgrade(b: BusinessState) -> void:
	b.bank(now_ms, content)
	b.level += 1
	b.upgrade_finish_ms = 0
	_emit("upgrade_complete", {"business": b.id, "level": b.level})


func _cmd_acquire(fid: String, bid: String) -> Dictionary:
	var b: BusinessState = businesses.get(bid)
	if b == null:
		return _fail("unknown_business")
	if b.owner_id != NEUTRAL_FACTION:
		return _fail("not_for_sale")
	if not "purchase" in content.business_type(b.type_id).get("acquisition", []):
		return _fail("not_for_sale")
	var price := purchase_price(b)
	var f: FactionState = factions[fid]
	if f.cash < price:
		return _fail("insufficient_cash")
	f.cash -= price
	b.owner_id = fid
	b.banked = 0
	b.last_accrual_ms = now_ms
	_emit("cash_changed", {"faction": fid, "cash": f.cash})
	_emit("business_acquired", {"business": b.id, "faction": fid, "price": price})
	return {"ok": true, "price": price}


func _cmd_move(fid: String, crew_id: String, cmd: Dictionary) -> Dictionary:
	var c: CrewState = crews.get(crew_id)
	if c == null or c.owner_id != fid:
		return _fail("not_owner")
	var dest: Dictionary
	var dest_landmark := ""
	if cmd.has("landmark"):
		dest_landmark = cmd["landmark"]
		if not landmark_locations.has(dest_landmark):
			return _fail("unknown_destination")
		dest = landmark_locations[dest_landmark]
	elif cmd.has("point"):
		var p: Array = cmd["point"]
		dest = roads.locate(Vector2i(int(p[0]), int(p[1])))
	else:
		return _fail("no_destination")
	return _start_route(c, dest, dest_landmark)


func _start_route(c: CrewState, dest: Dictionary, dest_landmark: String) -> Dictionary:
	var from := c.location
	if c.is_moving():
		var here := c.position_cm(now_ms, roads)
		from = roads.locate(Vector2i(roundi(here.x), roundi(here.y)))
	var r := roads.route(from, dest)
	if r.is_empty():
		return _fail("unreachable")
	_unstation(c)
	var speed_cms := maxi(1, roundi(float(content.vehicles.get(c.vehicle_id, {}).get("speed_mps", 10.0)) * 100.0))
	c.status = "moving"
	c.route_points = r["points"]
	c.route_costs = r.get("costs", [])
	c.route_cost = int(r.get("cost", r["length"]))
	c.route_length = r["length"]
	c.depart_ms = now_ms
	c.arrive_ms = now_ms + c.route_cost * 1000 / speed_cms
	c.dest_landmark = dest_landmark
	c.location = dest.duplicate()
	c.at_landmark = ""
	c.route_serial += 1
	_emit("crew_departed", {"crew": c.id, "destination": dest_landmark, "arrive_ms": c.arrive_ms})
	if c.arrive_ms <= now_ms:
		_arrive(c)
	return {"ok": true, "arrive_ms": c.arrive_ms, "length_cm": c.route_length}


func _arrive(c: CrewState) -> void:
	c.status = "idle"
	c.at_landmark = c.dest_landmark
	c.dest_landmark = ""
	c.route_points = []
	c.route_costs = []
	_station_if_possible(c)
	_emit("crew_arrived", {"crew": c.id, "landmark": c.at_landmark})


func _station_if_possible(c: CrewState) -> void:
	var b := business_at_landmark(c.at_landmark)
	if b != null and b.owner_id == c.owner_id and b.assigned_crew_id == "":
		b.assigned_crew_id = c.id
		_emit("crew_stationed", {"crew": c.id, "business": b.id})


func _unstation(c: CrewState) -> void:
	for b in businesses.values():
		if b.assigned_crew_id == c.id:
			b.assigned_crew_id = ""
			_emit("crew_unstationed", {"crew": c.id, "business": b.id})


# --- Rival AI ----------------------------------------------------------------------------
func _ai_tick() -> void:
	var fids := factions.keys()
	fids.sort()
	for fid in fids:
		var f: FactionState = factions[fid]
		if not f.ai:
			continue
		var owned: Array = []
		var bids := businesses.keys()
		bids.sort()
		for bid in bids:
			var b: BusinessState = businesses[bid]
			if b.owner_id == fid:
				owned.append(b)
				if b.stored(now_ms, content) * 2 >= b.capacity(content):
					_collect(b, b.stored(now_ms, content))
		var cids := crews.keys()
		cids.sort()
		for cid in cids:
			var c: CrewState = crews[cid]
			if c.owner_id != fid or c.is_moving() or not rng.chance_permille(450):
				continue
			# Patrol between family businesses and nearby street corners.
			if not owned.is_empty() and rng.chance_permille(600):
				var target: BusinessState = owned[rng.range_int(owned.size())]
				if target.landmark_id != c.at_landmark:
					_start_route(c, landmark_locations[target.landmark_id], target.landmark_id)
			else:
				var node := rng.range_int(roads.nodes.size())
				var adj: Array = roads.neighbours(node)
				if not adj.is_empty():
					var e: int = adj[0][0]
					_start_route(c, {"edge": e, "offset": int(roads.edges[e]["length"]) / 2}, "")


func _emit(type: String, data: Dictionary) -> void:
	data["type"] = type
	data["t"] = now_ms
	_events.append(data)


# --- Persistence ------------------------------------------------------------------------
func to_dict() -> Dictionary:
	var d := {
		"version": SAVE_VERSION, "now_ms": now_ms, "rng": rng.state, "player": player_faction_id,
		"ai_next_ms": ai_next_ms, "factions": [], "businesses": [], "crews": [], "headquarters": [],
	}
	for k in _sorted(factions):
		d["factions"].append(factions[k].to_dict())
	for k in _sorted(businesses):
		d["businesses"].append(businesses[k].to_dict())
	for k in _sorted(crews):
		var cd: Dictionary = crews[k].to_dict()
		cd["location"] = roads.location_to_key(crews[k].location)
		d["crews"].append(cd)
	for k in _sorted(headquarters):
		d["headquarters"].append(headquarters[k].to_dict())
	return d


## `legacy_roads` is the graph v1 saves were written against (Little Italy
## only); v1 crew locations are converted to points and re-located.
static func from_dict(d: Dictionary, p_content: GameContent, p_roads: RoadGraph, locations: Dictionary,
		legacy_roads: RoadGraph = null) -> SimWorld:
	var version := int(d.get("version", 0))
	if version != SAVE_VERSION and not (version == LEGACY_SAVE_VERSION and legacy_roads != null):
		return null
	var w := SimWorld.new()
	w.content = p_content
	w.roads = p_roads
	w.landmark_locations = locations
	w.now_ms = int(d["now_ms"])
	w.rng = SimRng.new(1)
	w.rng.state = int(d["rng"])
	w.player_faction_id = d.get("player", "")
	w.ai_next_ms = int(d.get("ai_next_ms", w.now_ms + AI_INTERVAL_MS))
	for f in d.get("factions", []):
		var fs := FactionState.from_dict(f)
		w.factions[fs.id] = fs
	for b in d.get("businesses", []):
		var bs := BusinessState.from_dict(b)
		w.businesses[bs.id] = bs
	for c in d.get("crews", []):
		var cs := CrewState.from_dict(c)
		var loc: Dictionary = c.get("location", {})
		if version == LEGACY_SAVE_VERSION:
			var legacy := {"edge": clampi(int(loc.get("edge", 0)), 0, legacy_roads.edges.size() - 1),
				"offset": int(loc.get("offset", 0))}
			cs.location = p_roads.locate(legacy_roads.location_point(legacy))
		else:
			cs.location = p_roads.location_from_key(loc)
			if cs.location.is_empty():
				cs.location = p_roads.locate(Vector2i(0, 0))
		if cs.at_landmark != "" and locations.has(cs.at_landmark) and not cs.is_moving():
			cs.location = locations[cs.at_landmark].duplicate()
		w.crews[cs.id] = cs
	for h in d.get("headquarters", []):
		var hs := HeadquartersState.from_dict(h)
		w.headquarters[hs.faction_id] = hs
	return w


static func _sorted(dict: Dictionary) -> Array:
	var k := dict.keys()
	k.sort()
	return k
