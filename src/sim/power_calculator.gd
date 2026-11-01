class_name PowerCalculator
extends RefCounted
## Power ratings from content data. Integer math (permille multipliers) keeps
## results identical on client and server.
##
## crew power = sum(soldiers x tier power)
##            x (1000 + capo leadership + vehicle bonus + research) / 1000
## Weapons, research and defensive positions plug in here as further permille
## terms or flat additions, never in presentation code.


static func soldier_base_power(soldiers: Dictionary, content: GameContent) -> int:
	var total := 0
	for tier in soldiers:
		total += int(soldiers[tier]) * int(content.soldier_tiers.get(tier, {}).get("power", 0))
	return total


static func crew_power(crew: CrewState, content: GameContent, research_permille := 0) -> int:
	var base := soldier_base_power(crew.soldiers, content)
	var capo: Dictionary = content.characters.get(crew.capo_id, {})
	var vehicle: Dictionary = content.vehicles.get(crew.vehicle_id, {})
	var mult := 1000 + int(capo.get("leadership_permille", 0)) + int(vehicle.get("power_bonus_permille", 0)) \
		+ research_permille
	return base * mult / 1000


static func crew_max_hp(soldiers: Dictionary, content: GameContent) -> int:
	var total := 0
	for tier in soldiers:
		total += int(soldiers[tier]) * int(content.soldier_tiers.get(tier, {}).get("hp", 0))
	return total


static func soldier_count(soldiers: Dictionary) -> int:
	var n := 0
	for tier in soldiers:
		n += int(soldiers[tier])
	return n


## Business defence: level rating plus the stationed crew's power, boosted by
## the stationed capo's business-defence abilities.
static func business_defence(biz: BusinessState, world: SimWorld) -> int:
	var lvl := world.content.business_level(biz.type_id, biz.level)
	var defence := int(lvl.get("defence", 0))
	if biz.assigned_crew_id != "" and world.crews.has(biz.assigned_crew_id):
		var crew: CrewState = world.crews[biz.assigned_crew_id]
		var bonus := 0
		var capo: Dictionary = world.content.characters.get(crew.capo_id, {})
		for ability_id in capo.get("abilities", []):
			bonus += int(world.content.abilities.get(ability_id, {}).get("effects", {}).get("business_defence_permille", 0))
		defence += crew_power(crew, world.content) * (1000 + bonus) / 1000
	return defence
