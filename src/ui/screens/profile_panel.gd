class_name ProfilePanel
extends RefCounted
## Player profile overlay: crest, boss and family, level, power, statistics
## and chapter progression. Reads the running session, or the save file when
## opened from the main menu (no world loaded).


static func open(parent: Node) -> Control:
	var m := UiKit.overlay(parent, 1180.0, "Profile")
	var body: VBoxContainer = m["body"]
	var s := summary()
	var p := App.profile
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 30)
	body.add_child(top)
	top.add_child(UiKit.crest(p.get("crest", "shield"), UiKit.initials_for(p.get("username", "")),
		Color(p.get("family_color", "#c9a24a")), 150))
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_theme_constant_override("separation", 4)
	top.add_child(who)
	who.add_child(UiTheme.label(String(p.get("username", "Boss")), 36, UiKit.IVORY, "display"))
	who.add_child(UiTheme.label(String(s.get("family", "")), 20, UiTheme.GOLD_LIGHT, "body_medium"))
	who.add_child(UiTheme.label("Local profile  ·  online account not connected", 15, UiTheme.FAINT, "body_medium"))
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 14)
	badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(badges)
	badges.add_child(_badge("Family level", str(s["level"]), "upgrade"))
	badges.add_child(_badge("Power", str(s["power"]), "power"))
	# Chapter progression.
	var prog := UiKit.panel(10, 0.25, 18)
	body.add_child(prog)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	prog.add_child(pv)
	var ph := HBoxContainer.new()
	pv.add_child(ph)
	var chap := UiTheme.caption("Chapter %d of %d  ·  %s" % [s["chapter"], s["chapters_total"], s["chapter_title"]],
		UiTheme.GOLD)
	chap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(chap)
	ph.add_child(UiTheme.caption("%d chapters completed" % s["completed"], UiTheme.MUTED))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.max_value = 1.0
	bar.value = float(s["completed"]) / maxf(1.0, float(s["chapters_total"]))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.GOLD
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	pv.add_child(bar)
	# Statistics.
	body.add_child(UiTheme.caption("Records", UiTheme.GOLD))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	for st in [["Cash", UiTheme.money(s["cash"])], ["Income", "%s/h" % UiTheme.money(s["income"])],
			["Businesses", str(s["businesses"])], ["Crews", str(s["crews"])], ["Soldiers", str(s["soldiers"])],
			["Collected", UiTheme.money(s["collected"])], ["Upgrades", str(s["upgrades"])],
			["Acquired", str(s["acquired"])], ["Boss since", s["since"]], ["Chapters done", str(s["completed"])]]:
		grid.add_child(_stat(st[0], st[1]))
	if not s["has_game"]:
		var n := UiTheme.label("No saved game on this device yet.", 16, UiTheme.MUTED, "body_medium")
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(n)
	return m["root"]


## Profile figures for the player family, from the live world or the save.
static func summary() -> Dictionary:
	var content: GameContent = Content.db
	var out := {"level": 1, "power": 0, "cash": 0, "income": 0, "businesses": 0, "crews": 0, "soldiers": 0,
		"collected": 0, "upgrades": 0, "acquired": 0, "completed": 0, "chapter": 1, "has_game": false,
		"family": "%s Family" % App.profile.get("family_name", ""), "chapters_total": content.chapters.size()}
	var game: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/Game")
	var w: SimWorld = game.world if game else null
	var businesses: Array = []
	var crews: Array = []
	var fid := ""
	var stats: Dictionary = {}
	if w:
		fid = w.player_faction_id
		businesses = w.businesses.values()
		crews = w.crews.values()
		stats = w.stats.get(fid, {})
		out["completed"] = w.chapter_index
		out["cash"] = (w.factions[fid] as FactionState).cash
		out["family"] = (w.factions[fid] as FactionState).name
		out["has_game"] = true
	elif App.save_exists():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://saves/slot_0.json"))
		if parsed is Dictionary and parsed.has("world"):
			var d: Dictionary = parsed["world"]
			fid = d.get("player", "")
			for b in d.get("businesses", []):
				businesses.append(BusinessState.from_dict(b))
			for c in d.get("crews", []):
				crews.append(CrewState.from_dict(c))
			stats = d.get("stats", {}).get(fid, {})
			out["completed"] = int(d.get("chapter_index", 0))
			for f in d.get("factions", []):
				if f.get("id") == fid:
					out["cash"] = int(f.get("cash", 0))
					out["family"] = f.get("name", out["family"])
			out["has_game"] = true
	for b in businesses:
		if b.owner_id == fid:
			out["businesses"] += 1
			out["income"] += b.net_per_hour(content)
	for c in crews:
		if c.owner_id == fid:
			out["crews"] += 1
			out["soldiers"] += PowerCalculator.soldier_count(c.soldiers)
			out["power"] += PowerCalculator.crew_power(c, content)
	for k in ["collected", "upgrades", "acquired"]:
		out[k] = int(stats.get(k, 0))
	out["level"] = out["completed"] + 1
	var idx := mini(out["completed"], maxi(0, out["chapters_total"] - 1))
	out["chapter"] = idx + 1
	out["chapter_title"] = String(content.chapters[idx].get("title", "")) if not content.chapters.is_empty() else ""
	var created := int(App.profile.get("created_ms", 0))
	out["since"] = Time.get_date_string_from_unix_time(created / 1000) if created > 0 else "—"
	return out


static func _badge(caption: String, value: String, icon_name: String) -> Control:
	var p := UiKit.panel(10, 0.4, 14)
	p.custom_minimum_size = Vector2(170, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UiTheme.icon_rect(icon_name, 26, UiTheme.GOLD))
	h.add_child(UiTheme.label(value, 30, UiKit.IVORY, "display"))
	v.add_child(h)
	var c := UiTheme.caption(caption, UiTheme.MUTED)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	return p


static func _stat(caption: String, value: String) -> Control:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.035)
	s.border_color = Color(UiTheme.GOLD, 0.14)
	s.border_width_bottom = 1
	s.set_corner_radius_all(6)
	s.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(208, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	v.add_child(UiTheme.caption(caption, UiTheme.MUTED))
	v.add_child(UiTheme.label(value, 22, UiKit.IVORY, "body_bold"))
	return p
