class_name SelectionPanelBuilder
extends RefCounted
## Fills the bottom selection sheet for a business, headquarters or crew.
## Layout: header (badge, title, owner, status, close) / stats + actions on one
## row / a thin progress or status line. Returns a refresh Callable(world, now).

const TYPE_ICONS := {"restaurant": "restaurant", "garage": "garage", "warehouse": "warehouse", "bar": "bar"}


static func build(parent: Control, sel: Dictionary, hud: Hud) -> Callable:
	var world := Game.world
	match sel.get("kind", ""):
		"business":
			return _business(parent, world, world.businesses[sel["id"]], hud)
		"hq":
			return _hq(parent, world, world.headquarters[sel["id"]], hud)
		"crew":
			return _crew(parent, world, world.crews[sel["id"]], hud)
	return Callable()


# --- Shared layout ---------------------------------------------------------------------
static func _frame(parent: Control, icon_name: String, title: String, subtitle: String, owner_color: Color,
		hud: Hud) -> Dictionary:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	parent.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var badge := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(1, 1, 1, 0.05)
	bs.border_color = Color(UiTheme.GOLD, 0.6)
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(22)
	bs.set_content_margin_all(9)
	bs.anti_aliasing = true
	badge.add_theme_stylebox_override("panel", bs)
	badge.add_child(UiTheme.icon_rect(icon_name, 24, UiTheme.GOLD_LIGHT))
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(badge)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(UiTheme.title(title, 24))
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 7)
	tv.add_child(sub)
	sub.add_child(UiTheme.dot(owner_color, 8))
	sub.add_child(UiTheme.label(subtitle, 16, UiTheme.MUTED, "body_medium"))
	var status := _status_pill()
	head.add_child(status["pill"])
	var close := UiTheme.icon_button("close", 36)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(hud.emit_close)
	head.add_child(close)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 22)
	v.add_child(line)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 22)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(stats)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(actions)
	return {"root": v, "stats": stats, "actions": actions, "status": status}


static func _status_pill() -> Dictionary:
	var pill := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.06)
	s.set_corner_radius_all(12)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	pill.add_theme_stylebox_override("panel", s)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UiTheme.label("", UiTheme.SIZE_CAPTION, UiTheme.MUTED, "caps")
	pill.add_child(l)
	return {"pill": pill, "label": l}


static func _set_status(status: Dictionary, text: String, color: Color) -> void:
	var l: Label = status["label"]
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", color)
	(status["pill"] as Control).visible = text != ""


static func _stat(row: HBoxContainer, caption: String) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(UiTheme.caption(caption))
	var value := UiTheme.label("-", 22, UiTheme.CREAM, "body_bold")
	box.add_child(value)
	row.add_child(box)
	return value


static func _progress_line(root: VBoxContainer, caption: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	root.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(UiTheme.caption(caption))
	var info := UiTheme.label("", UiTheme.SIZE_CAPTION + 1, UiTheme.MUTED, "body_medium")
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(info)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 5)
	box.add_child(bar)
	return {"info": info, "bar": bar}


static func _faction_color(world: SimWorld, fid: String) -> Color:
	var f := world.faction(fid)
	return Color.html(f.color) if f else UiTheme.MUTED


# --- Business -----------------------------------------------------------------------------
static func _business(parent: Control, world: SimWorld, b: BusinessState, hud: Hud) -> Callable:
	var type_def := world.content.business_type(b.type_id)
	var owner := world.faction(b.owner_id)
	var is_player := b.owner_id == world.player_faction_id
	var sub := "%s  ·  %s" % [type_def.get("name", b.type_id), owner.name if owner else "Unowned"]
	var f := _frame(parent, TYPE_ICONS.get(b.type_id, "cash"), b.name, sub, _faction_color(world, b.owner_id), hud)
	var stats: HBoxContainer = f["stats"]
	var level_l := _stat(stats, "Level")
	var income_l := _stat(stats, "Net / hr")
	var defence_l := _stat(stats, "Defence")
	var takings := _progress_line(f["root"], "Takings")
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
	var send := UiTheme.button("Send crew", "move", true)
	send.pressed.connect(hud.emit_action.bind("send_crew", {"landmark": b.landmark_id}))
	actions.add_child(send)

	return func(w: SimWorld, now: int) -> void:
		var max_level := w.content.business_max_level(b.type_id)
		level_l.text = "%d/%d" % [b.level, max_level]
		income_l.text = UiTheme.money(b.net_per_hour(w.content))
		defence_l.text = str(PowerCalculator.business_defence(b, w))
		if b.owner_id == SimWorld.NEUTRAL_FACTION:
			_set_status(f["status"], "Unclaimed", UiTheme.MUTED)
		else:
			var vuln := w.vulnerability(b)
			_set_status(f["status"], {"shielded": "Shielded", "guarded": "Guarded", "exposed": "Exposed"}[vuln],
				UiTheme.RED if vuln == "exposed" else UiTheme.GREEN)
		var stored := b.stored(now, w.content)
		var cap := b.capacity(w.content)
		var bar: ProgressBar = takings["bar"]
		bar.max_value = maxi(cap, 1)
		bar.value = stored if b.owner_id == w.player_faction_id else 0
		var info: Label = takings["info"]
		if b.owner_id == w.player_faction_id:
			var full_in := b.ms_until_full(now, w.content)
			info.text = "%s of %s  ·  %s" % [UiTheme.money(stored), UiTheme.money(cap),
				"full" if full_in == 0 else "full in " + UiTheme.duration(full_in)]
		elif b.owner_id == SimWorld.NEUTRAL_FACTION:
			info.text = "Not under family control"
		else:
			info.text = "Rival books are closed to you"
		if collect:
			collect.text = "COLLECT %s" % UiTheme.short_money(stored)
			collect.disabled = stored <= 0
		if upgrade:
			if b.is_upgrading(now):
				upgrade.text = UiTheme.duration(b.upgrade_finish_ms - now)
				upgrade.disabled = true
			elif b.level >= max_level:
				upgrade.text = "MAX LEVEL"
				upgrade.disabled = true
			else:
				var cost := int(b.level_def(w.content).get("upgrade_cost", 0))
				upgrade.text = "UPGRADE %s" % UiTheme.short_money(cost)
				upgrade.disabled = w.player().cash < cost
		if buy:
			var price := w.purchase_price(b)
			buy.text = "BUY %s" % UiTheme.short_money(price)
			buy.disabled = w.player().cash < price or b.owner_id != SimWorld.NEUTRAL_FACTION


# --- Headquarters ---------------------------------------------------------------------------
static func _hq(parent: Control, world: SimWorld, hq: HeadquartersState, hud: Hud) -> Callable:
	var owner := world.faction(hq.faction_id)
	var f := _frame(parent, "hq", hq.name, "Headquarters  ·  %s" % owner.name, _faction_color(world, hq.faction_id), hud)
	var stats: HBoxContainer = f["stats"]
	var level_l := _stat(stats, "HQ level")
	var biz_l := _stat(stats, "Businesses")
	var slots_l := _stat(stats, "Crew slots")
	var cap_l := _stat(stats, "Capacity")
	var fac := HFlowContainer.new()
	fac.add_theme_constant_override("h_separation", 6)
	fac.add_theme_constant_override("v_separation", 6)
	(f["root"] as VBoxContainer).add_child(fac)
	var defs: Dictionary = world.content.headquarters.get("facilities", {})
	for fid in defs:
		var lvl: int = hq.facilities.get(fid, 0)
		var chip := PanelContainer.new()
		var s := StyleBoxFlat.new()
		s.bg_color = Color(1, 1, 1, 0.06 if lvl > 0 else 0.02)
		s.set_corner_radius_all(10)
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 3
		s.content_margin_bottom = 3
		chip.add_theme_stylebox_override("panel", s)
		var unlock: int = defs[fid].get("unlock_hq_level", 1)
		var text: String = "%s  %d" % [defs[fid]["name"], lvl] if lvl > 0 else "%s  ·  HQ %d" % [defs[fid]["name"], unlock]
		chip.add_child(UiTheme.label(text, UiTheme.SIZE_CAPTION + 1, UiTheme.CREAM if lvl > 0 else UiTheme.FAINT,
			"body_medium"))
		fac.add_child(chip)
	var actions: HBoxContainer = f["actions"]
	var collect := UiTheme.button("Collect all", "cash")
	collect.pressed.connect(hud.emit_action.bind("collect_all", {}))
	actions.add_child(collect)
	var recall := UiTheme.button("Recall crews", "home", true)
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
		biz_l.text = "%d/%d" % [owned, int(ld.get("business_limit", 0))]
		slots_l.text = str(ld.get("crew_slots", 0))
		cap_l.text = str(ld.get("soldier_capacity", 0))
		_set_status(f["status"], "Home turf", UiTheme.GOLD_LIGHT)
		collect.text = "COLLECT %s" % UiTheme.short_money(total)
		collect.disabled = total <= 0


# --- Crew ------------------------------------------------------------------------------------
static func _crew(parent: Control, world: SimWorld, c: CrewState, hud: Hud) -> Callable:
	var owner := world.faction(c.owner_id)
	var capo: Dictionary = world.content.characters.get(c.capo_id, {})
	var rarity: Dictionary = world.content.rarities.get(capo.get("rarity", "common"), {})
	var f := _frame(parent, "crew", c.name, "Capo %s  ·  %s" % [capo.get("name", "?"), owner.name],
		_faction_color(world, c.owner_id), hud)
	var stats: HBoxContainer = f["stats"]
	var power_l := _stat(stats, "Power")
	var soldiers_l := _stat(stats, "Soldiers")
	var vehicle_l := _stat(stats, "Cars")
	var rarity_l := _stat(stats, "Capo")
	rarity_l.text = rarity.get("name", "")
	rarity_l.add_theme_color_override("font_color", Color.html(rarity.get("color", "#ffffff")))
	var health := _progress_line(f["root"], "Strength")
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.GREEN
	fill.set_corner_radius_all(3)
	(health["bar"] as ProgressBar).add_theme_stylebox_override("fill", fill)
	var actions: HBoxContainer = f["actions"]
	if c.owner_id == world.player_faction_id:
		var move := UiTheme.button("Move", "move")
		move.pressed.connect(hud.emit_action.bind("move_mode", {"crew": c.id}))
		actions.add_child(move)
		var recall := UiTheme.button("To HQ", "home", true)
		recall.pressed.connect(hud.emit_action.bind("recall", {"crew": c.id}))
		actions.add_child(recall)
	var follow := UiTheme.icon_button("follow", 48)
	follow.toggle_mode = true
	follow.tooltip_text = "Follow"
	follow.toggled.connect(func(on: bool): hud.emit_action("follow", {"crew": c.id, "on": on}))
	actions.add_child(follow)

	return func(w: SimWorld, now: int) -> void:
		power_l.text = str(w.crew_power(c.id))
		var parts := []
		for tier in c.soldiers:
			parts.append("%d %s" % [c.soldiers[tier], w.content.soldier_tiers.get(tier, {}).get("name", tier)])
		soldiers_l.text = str(PowerCalculator.soldier_count(c.soldiers))
		vehicle_l.text = str(c.vehicle_count)
		var info: Label = health["info"]
		info.text = hud.crew_status_text(w, c, now) + "   ·   " + ", ".join(parts)
		var bar: ProgressBar = health["bar"]
		bar.max_value = maxi(c.max_hp, 1)
		bar.value = c.hp
		if c.is_moving():
			_set_status(f["status"], "On the move", UiTheme.GOLD_LIGHT)
		else:
			_set_status(f["status"], "Ready", UiTheme.GREEN)
		follow.set_pressed_no_signal(hud.get_meta("following", "") == c.id)
