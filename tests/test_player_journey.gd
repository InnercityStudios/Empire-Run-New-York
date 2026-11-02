extends TestCase
## Player journey: chapter data and rules, the claim_chapter command, player
## statistics persistence, new-game identity and local profile validation.

const T0 := 1_000_000_000_000
const OBJECTIVE_TYPES := ["business_level", "own_business", "income", "businesses_owned", "collected_total",
	"upgrades_total", "family_power", "soldiers"]

var content: GameContent
var layout: DistrictLayout


func before_each() -> void:
	if content == null:
		content = GameContent.load_default()
		layout = DistrictLayout.build(content.districts["little_italy"], content.building_catalog)


func _world() -> SimWorld:
	return SimBootstrap.new_world(content, layout, "new_game", T0)


## Runs `body` with a temporary chapter list, restoring the real one after.
func _with_chapters(chapters: Array, body: Callable) -> void:
	var real := content.chapters
	content.chapters = chapters
	body.call()
	content.chapters = real


func test_thirty_chapters_are_well_formed() -> void:
	check_eq(content.chapters.size(), 30, "30 chapters")
	for i in content.chapters.size():
		var ch: Dictionary = content.chapters[i]
		check_eq(int(ch.get("number", 0)), i + 1, "chapter %d numbered" % (i + 1))
		check(not (ch.get("objectives", []) as Array).is_empty(), "chapter %d has objectives" % (i + 1))
		check(int(ch.get("rewards", {}).get("cash", 0)) > 0, "chapter %d has a reward" % (i + 1))
		for o in ch.get("objectives", []):
			check(String(o.get("type", "")) in OBJECTIVE_TYPES, "chapter %d objective type %s" % [i + 1, o.get("type")])
			check(String(o.get("text", "")) != "", "chapter %d objective has text" % (i + 1))
			if o.has("business"):
				check(_world().businesses.has(o["business"]), "chapter %d business %s exists" % [i + 1, o["business"]])


func test_chapter_one_starts_incomplete_and_cannot_be_claimed() -> void:
	var w := _world()
	check_eq(ChapterRules.status(w, "marino", 0), "active", "chapter 1 active")
	check_eq(ChapterRules.status(w, "marino", 1), "locked", "chapter 2 locked")
	check_eq(w.execute({"type": "claim_chapter", "faction": "marino"}).get("error"), "chapter_incomplete",
		"claim rejected")
	check_eq(w.chapter_index, 0, "still chapter 1")


func test_claim_chapter_pays_reward_and_advances() -> void:
	_with_chapters([
		{"number": 1, "objectives": [{"type": "businesses_owned", "target": 1}], "rewards": {"cash": 1234}},
		{"number": 2, "objectives": [{"type": "businesses_owned", "target": 99}], "rewards": {"cash": 1}},
	], func():
		var w := _world()
		w.drain_events()
		var cash := w.player().cash
		check_eq(ChapterRules.status(w, "marino", 0), "ready", "chapter ready")
		var r := w.execute({"type": "claim_chapter", "faction": "marino"})
		check(r.get("ok", false), "claim ok: %s" % str(r))
		check_eq(w.player().cash, cash + 1234, "reward paid")
		check_eq(w.chapter_index, 1, "advanced to chapter 2")
		check_eq(ChapterRules.status(w, "marino", 0), "done", "chapter 1 done")
		var types := w.drain_events().map(func(e): return e["type"])
		check("chapter_completed" in types, "chapter_completed event")
		check_eq(w.execute({"type": "claim_chapter", "faction": "marino"}).get("error"), "chapter_incomplete",
			"next chapter not claimable yet"))


func test_claim_respects_unlock_and_player_only() -> void:
	_with_chapters([
		{"number": 1, "unlock": {"family_power": 999999}, "objectives": [{"type": "businesses_owned", "target": 1}],
			"rewards": {"cash": 10}},
	], func():
		var w := _world()
		check_eq(ChapterRules.status(w, "marino", 0), "locked", "power gate locks chapter")
		check_eq(w.execute({"type": "claim_chapter", "faction": "marino"}).get("error"), "chapter_locked",
			"locked chapter not claimable")
		check_eq(w.execute({"type": "claim_chapter", "faction": "moretti"}).get("error"), "not_player",
			"AI families have no chapters"))


func test_objective_progress_reads_live_state() -> void:
	var w := _world()
	var p := ChapterRules.objective_progress(w, "marino", {"type": "own_business", "business": "biz_grand_freight"})
	check(not p["done"], "freight not owned")
	w.player().cash = 1_000_000
	w.execute({"type": "acquire_business", "faction": "marino", "business": "biz_grand_freight"})
	p = ChapterRules.objective_progress(w, "marino", {"type": "own_business", "business": "biz_grand_freight"})
	check(p["done"], "freight owned")
	check(p["landmark"] != "", "objective points at a landmark")


func test_statistics_count_and_persist() -> void:
	var w := _world()
	var r := w.execute({"type": "collect_business", "faction": "marino", "business": "biz_vesuvio"})
	w.player().cash = 1_000_000
	w.execute({"type": "acquire_business", "faction": "marino", "business": "biz_grand_freight"})
	var up := w.execute({"type": "upgrade_business", "faction": "marino", "business": "biz_bowery_auto"})
	w.advance_to(int(up["finish_ms"]))
	var s := w.stats_for("marino")
	check_eq(int(s["collected"]), int(r["amount"]), "collected total")
	check_eq(int(s["acquired"]), 1, "acquisitions")
	check_eq(int(s["upgrades"]), 1, "upgrades")
	w.chapter_index = 3
	var saved := JSON.stringify(w.to_dict())
	var restored := SimWorld.from_dict(JSON.parse_string(saved), content, w.roads, w.landmark_locations)
	check_eq(JSON.stringify(restored.to_dict()), saved, "stats and chapter survive a save")
	check_eq(restored.chapter_index, 3, "chapter index restored")


func test_saves_without_journey_fields_still_load() -> void:
	var w := _world()
	var d := w.to_dict()
	d.erase("stats")
	d.erase("chapter_index")
	var restored := SimWorld.from_dict(JSON.parse_string(JSON.stringify(d)), content, w.roads, w.landmark_locations)
	check(restored != null, "older save loads")
	check_eq(restored.chapter_index, 0, "defaults to chapter 1")
	check(restored.stats.is_empty(), "empty statistics")


func test_new_game_takes_family_identity() -> void:
	var w := _world()
	w.apply_identity("marino", "Ferraro", "Nicky", "#8a2e35")
	check_eq(w.player().name, "Ferraro Family", "family name")
	check_eq(w.player().boss, "Nicky", "boss")
	check_eq(w.player().color, "#8a2e35", "colour")
	check_eq((w.headquarters["marino"] as HeadquartersState).name, "Ferraro Social Club", "HQ named for the family")


func test_profile_name_validation() -> void:
	var app: GDScript = load("res://src/app/app_state.gd")
	check_eq(app.validate_username("Nicky"), "", "valid name")
	check_eq(app.validate_username("Vito_77"), "", "digits and underscore")
	check(app.validate_username("Al") != "", "too short")
	check(app.validate_username("ThisNameIsTooLong1") != "", "too long")
	check(app.validate_username("7Up") != "", "must start with a letter")
	check(app.validate_username("Nick!") != "", "no symbols")
	check_eq(app.validate_family("D'Amico"), "", "apostrophe allowed")
	check_eq(app.validate_family("Di Napoli"), "", "space allowed")
	check(app.validate_family("X") != "", "family too short")
	check(app.validate_family("Ferr4ro") != "", "no digits in family name")


func test_settings_defaults_are_complete() -> void:
	var app: GDScript = load("res://src/app/app_state.gd")
	var d: Dictionary = app.DEFAULTS
	for k in ["master", "music", "sfx", "ambience", "dialogue"]:
		var v := float(d["audio"][k])
		check(v >= 0.0 and v <= 1.0, "audio %s in range" % k)
	check(String(d["graphics"]["quality"]) in ["low", "medium", "high"], "quality default")
	check(int(d["graphics"]["fps"]) in [30, 60], "fps default")
	for k in ["haptics", "tips", "dialogue_auto", "language"]:
		check(d["gameplay"].has(k), "gameplay %s" % k)


func test_dialogue_and_tips_data_parse() -> void:
	var dlg: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogue/ch01_intro.json"))
	check(dlg is Dictionary and not (dlg["lines"] as Array).is_empty(), "chapter 1 intro has lines")
	for line in dlg["lines"]:
		check(String(line.get("id", "")) != "" and String(line.get("text", "")) != "", "line has id and text")
	var tips: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/tips.json"))
	check(tips is Dictionary and (tips["tips"] as Array).size() >= 5, "tips present")
	for ch in content.chapters:
		var id := String(ch.get("intro_dialogue", ""))
		if id != "":
			check(FileAccess.file_exists("res://data/dialogue/%s.json" % id), "dialogue %s exists" % id)
