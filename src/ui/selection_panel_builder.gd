class_name SelectionPanelBuilder
extends RefCounted
## Fills the bottom selection card for a business, headquarters or crew.
## Returns a refresh Callable(world, now_ms) that updates live values.

const TYPE_ICONS := {"restaurant": "restaurant", "garage": "garage", "warehouse": "warehouse", "bar": "bar"}


static func build(panel: DecoPanel, sel: Dictionary, hud: Hud) -> Callable:
	var world := Game.world
	match sel.get("kind", ""):
		"business":
			return _business(panel, world, world.businesses[sel["id"]], hud)
		"hq":
			return _hq(panel, world, world.headquarters[sel["id"]], hud)
		"crew":
			return _crew(panel, world, world.crews[sel["id"]], hud)
	return Callable()


# --- Shared layout ---------------------------------------------------------------------
static func _frame(panel: DecoPanel, icon_name: String, title: String, subtitle: String, sub_color: Color,
		hud: Hud) -> Dictionary:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var badge := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0, 0, 0, 0.5)
	bs.border_color = UiTheme.GOLD
	bs.set_border_width_all(2)
	bs.set_corner_radius_all(40)
	bs.set_content_margin_all(10)
	badge.add_theme_stylebox_override("panel", bs)
	badge.add_child(UiTheme.icon_rect(icon_name, 46, UiTheme.GOLD_LIGHT))
	head.add_child(badge)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(UiTheme.title(title, 36))
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 8)
	tv.add_child(sub)
	var dot := ColorRect.new()
	dot.color = sub_color
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.add_child(dot)
	sub.add_child(UiTheme.label(subtitle, 23, UiTheme.MUTED, "body_bold"))
	var close := UiTheme.button("", "close", true)
	close.custom_minimum_size = Vector2(60, 56)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(hud.emit_close)
	head.add_child(close)
	var sep := ColorRect.new()
	sep.color = Color(UiTheme.GOLD, 0.35)
	sep.custom_minimum_size = Vector2(0, 1)
	v.add_child(sep)
	var stats := GridContainer.new()
	stats.columns = 4
	stats.add_theme_constant_override("h_separation", 34)
	stats.add_theme_constant_override("v_separation", 6)
	v.add_child(stats)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	actions.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(actions)
	return {"root": v, "stats": stats, "actions": actions}


static func _stat(grid: GridContainer, caption: String) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	box.add_child(UiTheme.label(caption.to_upper(), 18, UiTheme.MUTED, "body_bold"))
	var value := UiTheme.label("-", 28, UiTheme.CREAM, "body_bold")
	box.add_child(value)
	grid.add_child(box)
	return value


static func _faction_color(world: SimWorld, fid: String) -> Color:
	var f := world.faction(fid)
	return Color.html(f.color) if f else UiTheme.MUTED


# --- Business -----------------------------------------------------------------------------
static func _business(panel: DecoPanel, world: SimWorld, b: BusinessState, hud: Hud) -> Callable:
	var type_def := world.content.business_type(b.type_id)
	var owner := world.faction(b.owner_id)
	var is_player := b.owner_id == world.player_faction_id
	var sub := "%s  ·  %s" % [type_def.get("name", b.type_id), owner.name if owner else "Unowned"]
	var f := _frame(panel, TYPE_ICONS.get(b.type_id, "cash"), b.name, sub, _faction_color(world, b.owner_id), hud)
	var grid: GridContainer = f["stats"]
	var level_l := _stat(grid, "Level")
	var income_l := _stat(grid, "Net income")
	var defence_l := _stat(grid, "Defence")
	var status_l := _stat(grid, "Status")
	var storage_box := VBoxContainer.new()
	storage_box.add_theme_constant_override("separation", 4)
	(f["root"] as VBoxContainer).add_child(storage_box)
	(f["root"] as VBoxContainer).move_child(storage_box, 3)
	var storage_head := HBoxContainer.new()
	storage_box.add_child(storage_head)
	storage_head.add_child(UiTheme.label("TAKINGS", 18, UiTheme.MUTED, "body_bold"))
	var storage_l := UiTheme.label("", 22, UiTheme.CREAM)
	storage_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	storage_head.add_child(storage_l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	storage_box.add_child(bar)
	var desc := UiTheme.label(type_def.get("description", ""), 21, UiTheme.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(900, 0)
	(f["root"] as VBoxContainer).add_child(desc)
	(f["root"] as VBoxContainer).move_child(desc, 2)
	var actions: HBoxContainer = f["actions"]
	var collect: Button
	var upgrade: Button
	var buy: Button
	if is_player:
		collect = UiTheme.button("Collect", "cash")
		collect.pressed.connect(hud.emit_action.bind("collect", {"business": b.id}))
		actions.add_child(collect)
		upgrade = UiTheme.button("Upgrade", "upgrade", true)
		upgrade.pressed.connect(hud.emit_action.bind("upgrade", {"business": b.id}))
		actions.add_child(upgrade)
	elif b.owner_id == SimWorld.NEUTRAL_FACTION:
		buy = UiTheme.button("Buy", "buy")
		buy.pressed.connect(hud.emit_action.bind("buy", {"business": b.id}))
		actions.add_child(buy)
	else:
		var note := UiTheme.label("Moretti territory. Move a crew in to keep watch.", 22, UiTheme.MUTED)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(note)
	var send := UiTheme.button("Send Crew", "move", true)
	send.pressed.connect(hud.emit_action.bind("send_crew", {"landmark": b.landmark_id}))
	actions.add_child(send)

	return func(w: SimWorld, now: int) -> void:
		var producing := b.is_producing()
		var max_level := w.content.business_max_level(b.type_id)
		level_l.text = "%d / %d" % [b.level, max_level]
		income_l.text = "%s/h" % UiTheme.money(b.net_per_hour(w.content))
		defence_l.text = str(PowerCalculator.business_defence(b, w))
		var vuln := w.vulnerability(b)
		if b.owner_id == SimWorld.NEUTRAL_FACTION:
			status_l.text = "Unclaimed"
			status_l.add_theme_color_override("font_color", UiTheme.MUTED)
		else:
			status_l.text = {"shielded": "Shielded", "guarded": "Guarded", "exposed": "Exposed"}[vuln]
			status_l.add_theme_color_override("font_color", UiTheme.RED if vuln == "exposed" else UiTheme.GREEN)
		var stored := b.stored(now, w.content)
		var cap := b.capacity(w.content)
		bar.max_value = maxi(cap, 1)
		bar.value = stored if producing and b.owner_id == w.player_faction_id else 0
		if b.owner_id == w.player_faction_id:
			var full_in := b.ms_until_full(now, w.content)
			storage_l.text = "%s / %s  ·  %s" % [UiTheme.money(stored), UiTheme.money(cap),
				"Full" if full_in == 0 else "full in " + UiTheme.duration(full_in)]
		elif b.owner_id == SimWorld.NEUTRAL_FACTION:
			storage_l.text = "Not under family control"
		else:
			storage_l.text = "Rival books are closed to you"
		if collect:
			collect.text = "COLLECT %s" % UiTheme.money(stored)
			collect.disabled = stored <= 0
		if upgrade:
			if b.is_upgrading(now):
				upgrade.text = "UPGRADING · %s" % UiTheme.duration(b.upgrade_finish_ms - now)
				upgrade.disabled = true
			elif b.level >= max_level:
				upgrade.text = "MAX LEVEL"
				upgrade.disabled = true
			else:
				var cost := int(b.level_def(w.content).get("upgrade_cost", 0))
				upgrade.text = "UPGRADE %s" % UiTheme.money(cost)
				upgrade.disabled = w.player().cash < cost
		if buy:
			var price := w.purchase_price(b)
			buy.text = "BUY %s" % UiTheme.money(price)
			buy.disabled = w.player().cash < price or b.owner_id != SimWorld.NEUTRAL_FACTION


# --- Headquarters ---------------------------------------------------------------------------
static func _hq(panel: DecoPanel, world: SimWorld, hq: HeadquartersState, hud: Hud) -> Callable:
	var owner := world.faction(hq.faction_id)
	var f := _frame(panel, "hq", hq.name, "Headquarters  ·  %s" % owner.name, _faction_color(world, hq.faction_id), hud)
	var grid: GridContainer = f["stats"]
	var level_l := _stat(grid, "HQ Level")
	var biz_l := _stat(grid, "Businesses")
	var slots_l := _stat(grid, "Crew slots")
	var cap_l := _stat(grid, "Soldier capacity")
	var fac := HFlowContainer.new()
	fac.add_theme_constant_override("h_separation", 10)
	fac.add_theme_constant_override("v_separation", 8)
	(f["root"] as VBoxContainer).add_child(fac)
	(f["root"] as VBoxContainer).move_child(fac, 3)
	var defs: Dictionary = world.content.headquarters.get("facilities", {})
	for fid in defs:
		var lvl: int = hq.facilities.get(fid, 0)
		var chip := PanelContainer.new()
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0, 0, 0, 0.45)
		s.border_color = UiTheme.GOLD_DARK if lvl > 0 else Color(0.25, 0.23, 0.2)
		s.set_border_width_all(1)
		s.set_content_margin_all(8)
		s.content_margin_left = 12
		s.content_margin_right = 12
		chip.add_theme_stylebox_override("panel", s)
		var unlock: int = defs[fid].get("unlock_hq_level", 1)
		var text: String = "%s  Lv %d" % [defs[fid]["name"], lvl] if lvl > 0 else "%s  ·  HQ %d" % [defs[fid]["name"], unlock]
		chip.add_child(UiTheme.label(text, 21, UiTheme.CREAM if lvl > 0 else UiTheme.MUTED, "body_bold"))
		fac.add_child(chip)
	var actions: HBoxContainer = f["actions"]
	var collect := UiTheme.button("Collect All", "cash")
	collect.pressed.connect(hud.emit_action.bind("collect_all", {}))
	actions.add_child(collect)
	var recall := UiTheme.button("Recall Crews", "home", true)
	recall.pressed.connect(hud.emit_action.bind("recall_all", {}))
	actions.add_child(recall)

	return func(w: SimWorld, now: int) -> void:
		var ld := hq.level_def(w.content)
		level_l.text = str(hq.level)
		var owned := 0
		var total := 0
		for b in w.businesses.values():
			if b.owner_id == hq.faction_id:
				owned += 1
				total += b.stored(now, w.content)
		biz_l.text = "%d / %d" % [owned, int(ld.get("business_limit", 0))]
		slots_l.text = str(ld.get("crew_slots", 0))
		cap_l.text = str(ld.get("soldier_capacity", 0))
		collect.text = "COLLECT ALL %s" % UiTheme.money(total)
		collect.disabled = total <= 0


# --- Crew ------------------------------------------------------------------------------------
static func _crew(panel: DecoPanel, world: SimWorld, c: CrewState, hud: Hud) -> Callable:
	var owner := world.faction(c.owner_id)
	var capo: Dictionary = world.content.characters.get(c.capo_id, {})
	var rarity: Dictionary = world.content.rarities.get(capo.get("rarity", "common"), {})
	var f := _frame(panel, "crew", c.name, "%s  ·  Capo %s" % [owner.name, capo.get("name", "?")],
		_faction_color(world, c.owner_id), hud)
	var grid: GridContainer = f["stats"]
	var power_l := _stat(grid, "Power")
	var soldiers_l := _stat(grid, "Soldiers")
	var vehicle_l := _stat(grid, "Vehicles")
	var rarity_l := _stat(grid, "Capo rarity")
	rarity_l.text = rarity.get("name", "")
	rarity_l.add_theme_color_override("font_color", Color.html(rarity.get("color", "#ffffff")))
	var status_l := UiTheme.label("", 24, UiTheme.CREAM)
	(f["root"] as VBoxContainer).add_child(status_l)
	(f["root"] as VBoxContainer).move_child(status_l, 3)
	var hp := ProgressBar.new()
	hp.show_percentage = false
	hp.custom_minimum_size = Vector2(0, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.GREEN
	hp.add_theme_stylebox_override("fill", fill)
	(f["root"] as VBoxContainer).add_child(hp)
	(f["root"] as VBoxContainer).move_child(hp, 4)
	var actions: HBoxContainer = f["actions"]
	var follow: Button
	if c.owner_id == world.player_faction_id:
		var move := UiTheme.button("Move", "move")
		move.pressed.connect(hud.emit_action.bind("move_mode", {"crew": c.id}))
		actions.add_child(move)
		var recall := UiTheme.button("Return to HQ", "home", true)
		recall.pressed.connect(hud.emit_action.bind("recall", {"crew": c.id}))
		actions.add_child(recall)
	else:
		var bio := UiTheme.label(capo.get("bio", ""), 21, UiTheme.MUTED)
		bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(bio)
	follow = UiTheme.button("Follow", "follow", true)
	follow.toggle_mode = true
	follow.toggled.connect(func(on: bool): hud.emit_action("follow", {"crew": c.id, "on": on}))
	actions.add_child(follow)

	return func(w: SimWorld, now: int) -> void:
		power_l.text = str(w.crew_power(c.id))
		var parts := []
		for tier in c.soldiers:
			parts.append("%d %s" % [c.soldiers[tier], w.content.soldier_tiers.get(tier, {}).get("name", tier)])
		soldiers_l.text = str(PowerCalculator.soldier_count(c.soldiers))
		soldiers_l.tooltip_text = ", ".join(parts)
		vehicle_l.text = "%d × %s" % [c.vehicle_count, w.content.vehicles.get(c.vehicle_id, {}).get("name", "")]
		status_l.text = hud.crew_status_text(w, c, now) + "   ·   " + ", ".join(parts)
		hp.max_value = maxi(c.max_hp, 1)
		hp.value = c.hp
		follow.set_pressed_no_signal(hud.get_meta("following", "") == c.id)
