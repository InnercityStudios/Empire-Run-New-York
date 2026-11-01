extends TestCase
## Simulation rules: economy, upgrades, acquisition, movement, determinism, saves.

const T0 := 1_000_000_000_000
const HOUR := 3_600_000

var content: GameContent
var layout: DistrictLayout


func before_each() -> void:
	if content == null:
		content = GameContent.load_default()
		layout = DistrictLayout.build(content.districts["little_italy"], content.building_catalog)


func _world() -> SimWorld:
	return SimBootstrap.new_world(content, layout, "new_game", T0)


func test_content_loads_without_errors() -> void:
	check(content.errors.is_empty(), "content errors: %s" % ", ".join(content.errors))
	check(content.business_types.size() >= 4, "business types loaded")


func test_starting_income_is_stored() -> void:
	var w := _world()
	var b: BusinessState = w.businesses["biz_vesuvio"]
	var rate := b.net_per_hour(content)
	check_eq(b.stored(T0, content), rate * 3 / 2, "1.5 hours of stored income")


func test_income_caps_at_storage() -> void:
	var w := _world()
	var b: BusinessState = w.businesses["biz_vesuvio"]
	check_eq(b.stored(T0 + 100 * HOUR, content), b.capacity(content), "storage cap")


func test_collect_moves_cash_and_resets() -> void:
	var w := _world()
	var cash := w.player().cash
	var r := w.execute({"type": "collect_business", "faction": "marino", "business": "biz_vesuvio"})
	check(r["ok"], "collect ok")
	check_eq(w.player().cash, cash + int(r["amount"]), "cash increased")
	check_eq(w.businesses["biz_vesuvio"].stored(T0, content), 0, "storage emptied")
	var again := w.execute({"type": "collect_business", "faction": "marino", "business": "biz_vesuvio"})
	check_eq(again.get("error"), "nothing_to_collect", "second collect rejected")


func test_cannot_collect_rival_business() -> void:
	var w := _world()
	var r := w.execute({"type": "collect_business", "faction": "marino", "business": "biz_napoli"})
	check_eq(r.get("error"), "not_owner", "rival business protected")


func test_upgrade_timer_and_banking() -> void:
	var w := _world()
	var b: BusinessState = w.businesses["biz_bowery_auto"]
	var before := b.stored(T0, content)
	var r := w.execute({"type": "upgrade_business", "faction": "marino", "business": b.id})
	check(r["ok"], "upgrade started: %s" % str(r))
	check_eq(b.level, 1, "level unchanged while upgrading")
	check(w.execute({"type": "upgrade_business", "faction": "marino", "business": b.id}).get("error") == "already_upgrading",
		"no double upgrade")
	w.advance_to(int(r["finish_ms"]))
	check_eq(b.level, 2, "level after timer")
	check(b.stored(w.now_ms, content) >= before, "income banked across level change")


func test_purchase_neutral_business() -> void:
	var w := _world()
	var b: BusinessState = w.businesses["biz_grand_freight"]
	w.player().cash = 1_000_000
	var price := w.purchase_price(b)
	var r := w.execute({"type": "acquire_business", "faction": "marino", "business": b.id})
	check(r["ok"], "purchase ok")
	check_eq(b.owner_id, "marino", "ownership transferred")
	check_eq(w.player().cash, 1_000_000 - price, "price charged")
	check_eq(w.execute({"type": "acquire_business", "faction": "marino", "business": "biz_napoli"}).get("error"),
		"not_for_sale", "rival business not purchasable")


func test_purchase_requires_cash() -> void:
	var w := _world()
	w.player().cash = 10
	var r := w.execute({"type": "acquire_business", "faction": "marino", "business": "biz_grand_freight"})
	check_eq(r.get("error"), "insufficient_cash", "insufficient cash")


func test_crew_moves_along_streets_and_arrives() -> void:
	var w := _world()
	var r := w.execute({"type": "move_crew", "faction": "marino", "crew": "crew_mulberry", "landmark": "lm_grand_freight"})
	check(r["ok"], "move accepted: %s" % str(r))
	var c: CrewState = w.crews["crew_mulberry"]
	check(c.is_moving(), "crew moving")
	check(c.route_points.size() >= 3, "route turns through intersections")
	# Every route leg is axis-aligned (follows the street grid).
	for i in c.route_points.size() - 1:
		var a: Vector2i = c.route_points[i]
		var b: Vector2i = c.route_points[i + 1]
		check(a.x == b.x or a.y == b.y, "leg %d follows a street" % i)
	w.advance_to(int(r["arrive_ms"]))
	check(not c.is_moving(), "arrived")
	check_eq(c.at_landmark, "lm_grand_freight", "at destination")


func test_crew_station_and_unstation() -> void:
	var w := _world()
	var b: BusinessState = w.businesses["biz_bowery_auto"]
	check_eq(b.assigned_crew_id, "crew_bowery", "starting crew stationed at its business")
	check_eq(w.vulnerability(b), "guarded", "guarded while stationed")
	var defence_guarded := PowerCalculator.business_defence(b, w)
	w.execute({"type": "move_crew", "faction": "marino", "crew": "crew_bowery", "landmark": "lm_vesuvio"})
	check_eq(b.assigned_crew_id, "", "unstationed on departure")
	check(PowerCalculator.business_defence(b, w) < defence_guarded, "defence drops without crew")


func test_cannot_command_rival_crew() -> void:
	var w := _world()
	var r := w.execute({"type": "move_crew", "faction": "marino", "crew": "crew_moretti_1", "landmark": "lm_vesuvio"})
	check_eq(r.get("error"), "not_owner", "rival crew protected")


func test_power_formula() -> void:
	var w := _world()
	var c: CrewState = w.crews["crew_mulberry"]
	# 10 associates x 8 + 4 soldiers x 15 = 140; x (1000 + 120 capo + 30 vehicle) / 1000 = 161
	check_eq(PowerCalculator.crew_power(c, content), 161, "crew power")
	check(w.crew_power("crew_moretti_1") > w.crew_power("crew_mulberry"), "rival heavies outgun starting crew")


func test_simulation_is_deterministic() -> void:
	var a := _world()
	var b := _world()
	for w in [a, b]:
		w.execute({"type": "move_crew", "faction": "marino", "crew": "crew_mulberry", "landmark": "lm_blue_lantern"})
		w.advance_to(T0 + 10 * 60_000)
		w.execute({"type": "collect_all", "faction": "marino"})
		w.advance_to(T0 + 30 * 60_000)
	check_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), "identical state from identical inputs")


func test_save_round_trip() -> void:
	var w := _world()
	w.execute({"type": "move_crew", "faction": "marino", "crew": "crew_mulberry", "landmark": "lm_bowery_auto"})
	w.advance_to(T0 + 5_000)
	var saved := JSON.stringify(w.to_dict())
	var restored := SimWorld.from_dict(JSON.parse_string(saved), content, w.roads, w.landmark_locations)
	check(restored != null, "restored")
	check_eq(JSON.stringify(restored.to_dict()), saved, "round trip is lossless")
	restored.advance_to(T0 + 600_000)
	w.advance_to(T0 + 600_000)
	check_eq(JSON.stringify(restored.to_dict()), JSON.stringify(w.to_dict()), "continues identically after load")


func test_offline_catch_up_is_bounded() -> void:
	var w := _world()
	var t := Time.get_ticks_msec()
	w.advance_to(T0 + 48 * HOUR)
	check(Time.get_ticks_msec() - t < 2000, "48h offline catch-up is fast")
	check_eq(w.businesses["biz_vesuvio"].stored(w.now_ms, content), w.businesses["biz_vesuvio"].capacity(content),
		"offline income accrued to cap")
