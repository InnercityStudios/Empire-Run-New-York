class_name BusinessState
extends RefCounted
## A business on the map. Income accrues lazily from timestamps:
## stored(now) = min(capacity, banked + net_rate * (now - last_accrual_ms)).
## Nothing ticks per frame, so offline time and server catch-up are exact.

const MS_PER_HOUR := 3_600_000

var id := ""
var type_id := ""
var name := ""
var landmark_id := ""
var owner_id := ""
var level := 1
var banked := 0
var last_accrual_ms := 0
var assigned_crew_id := ""
var upgrade_finish_ms := 0
var shield_until_ms := 0
var last_attacked_ms := 0
var territory := ""


func level_def(content: GameContent) -> Dictionary:
	return content.business_level(type_id, level)


func net_per_hour(content: GameContent) -> int:
	var l := level_def(content)
	return maxi(0, int(l.get("income_per_hour", 0)) - int(l.get("upkeep_per_hour", 0)))


func capacity(content: GameContent) -> int:
	return net_per_hour(content) * int(level_def(content).get("storage_hours", 1))


func is_producing() -> bool:
	return owner_id != "" and owner_id != SimWorld.NEUTRAL_FACTION


func stored(now_ms: int, content: GameContent) -> int:
	if not is_producing():
		return 0
	var elapsed := maxi(0, now_ms - last_accrual_ms)
	return mini(capacity(content), banked + net_per_hour(content) * elapsed / MS_PER_HOUR)


## Fold accrued income into `banked` (before the rate changes).
func bank(now_ms: int, content: GameContent) -> void:
	banked = stored(now_ms, content)
	last_accrual_ms = now_ms


## Milliseconds until storage is full (0 when full or not producing).
func ms_until_full(now_ms: int, content: GameContent) -> int:
	var rate := net_per_hour(content)
	if rate <= 0 or not is_producing():
		return 0
	var missing := capacity(content) - stored(now_ms, content)
	return maxi(0, missing * MS_PER_HOUR / rate)


func is_upgrading(now_ms: int) -> bool:
	return upgrade_finish_ms > now_ms


func to_dict() -> Dictionary:
	return {
		"id": id, "type": type_id, "name": name, "landmark": landmark_id, "owner": owner_id, "level": level,
		"banked": banked, "last_accrual_ms": last_accrual_ms, "assigned_crew": assigned_crew_id,
		"upgrade_finish_ms": upgrade_finish_ms, "shield_until_ms": shield_until_ms,
		"last_attacked_ms": last_attacked_ms, "territory": territory,
	}


static func from_dict(d: Dictionary) -> BusinessState:
	var b := BusinessState.new()
	b.id = d["id"]
	b.type_id = d["type"]
	b.name = d.get("name", "")
	b.landmark_id = d.get("landmark", "")
	b.owner_id = d.get("owner", "")
	b.level = int(d.get("level", 1))
	b.banked = int(d.get("banked", 0))
	b.last_accrual_ms = int(d.get("last_accrual_ms", 0))
	b.assigned_crew_id = d.get("assigned_crew", "")
	b.upgrade_finish_ms = int(d.get("upgrade_finish_ms", 0))
	b.shield_until_ms = int(d.get("shield_until_ms", 0))
	b.last_attacked_ms = int(d.get("last_attacked_ms", 0))
	b.territory = d.get("territory", "")
	return b
