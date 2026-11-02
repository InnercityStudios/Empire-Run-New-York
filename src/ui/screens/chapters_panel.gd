class_name ChaptersPanel
extends RefCounted
## Chapter book: the 30 chapters with their state, and the selected chapter's
## objectives, live progress, unlock requirement and reward. Claiming goes
## through the simulation's validated "claim_chapter" command.

const STATUS_TEXT := {"done": "Completed", "ready": "Reward ready", "active": "In progress", "locked": "Locked"}


static func open(parent: Node, on_claim: Callable) -> Control:
	var m := UiKit.overlay(parent, 1360.0, "Chapters")
	var body: VBoxContainer = m["body"]
	var world := Game.world
	var fid := Game.player_id
	var chapters: Array = world.content.chapters
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.custom_minimum_size = Vector2(0, 640)
	body.add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 14)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(detail)
	var rows: Array = []
	var select := func(i: int) -> void:
		for j in rows.size():
			(rows[j] as Button).button_pressed = j == i
		_detail(detail, world, fid, chapters, i, func():
			UiKit.close_modal(m["root"])
			on_claim.call())
	for i in chapters.size():
		var b := _row(chapters[i], ChapterRules.status(world, fid, i))
		var idx := i
		b.pressed.connect(func(): select.call(idx))
		list.add_child(b)
		rows.append(b)
	var current := mini(world.chapter_index, chapters.size() - 1)
	select.call(current)
	# Bring the current chapter into view once the list has its layout.
	scroll.ready.connect(func(): scroll.ensure_control_visible.call_deferred(rows[current]))
	return m["root"]


static func _row(ch: Dictionary, status: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 70)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var s := StyleBoxFlat.new()
		var on: bool = state in ["pressed", "hover_pressed"]
		s.bg_color = Color(UiTheme.GOLD, 0.14) if on else Color(1, 1, 1, 0.03 if state == "normal" else 0.06)
		s.border_color = UiTheme.GOLD
		s.border_width_left = 3 if on else 0
		s.set_corner_radius_all(6)
		b.add_theme_stylebox_override(state, s)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16
	h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var num := UiTheme.label("%02d" % int(ch.get("number", 0)), 26,
		UiTheme.FAINT if status == "locked" else UiTheme.GOLD, "display")
	num.custom_minimum_size = Vector2(44, 0)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(num)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	v.add_child(UiTheme.label(String(ch.get("title", "")), 20,
		UiTheme.MUTED if status == "locked" else UiKit.IVORY, "body_bold"))
	v.add_child(UiTheme.label(STATUS_TEXT[status], 15,
		UiTheme.GOLD_LIGHT if status == "ready" else UiTheme.MUTED, "body_medium"))
	var icon: String = {"done": "check", "ready": "cash", "active": "target", "locked": "lock"}[status]
	var ic := UiTheme.icon_rect(icon, 22, UiTheme.GOLD if status != "locked" else UiTheme.FAINT)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	return b


static func _detail(box: VBoxContainer, world: SimWorld, fid: String, chapters: Array, i: int,
		claim: Callable) -> void:
	for c in box.get_children():
		c.queue_free()
	var ch: Dictionary = chapters[i]
	var status := ChapterRules.status(world, fid, i)
	box.add_child(UiTheme.label("CHAPTER %d  ·  %s" % [int(ch.get("number", i + 1)), STATUS_TEXT[status].to_upper()],
		16, UiTheme.GOLD, "caps"))
	box.add_child(UiTheme.label(String(ch.get("title", "")), 38, UiKit.IVORY, "display"))
	var summary := UiTheme.label(String(ch.get("summary", "")), 20, UiTheme.MUTED, "body_medium")
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(summary)
	if bool(ch.get("placeholder", false)):
		box.add_child(UiTheme.label("Placeholder objectives: story content awaits approval.", 15, UiTheme.FAINT,
			"body_medium"))
	box.add_child(UiTheme.label("OBJECTIVES", 16, UiTheme.GOLD, "caps"))
	var live := status in ["active", "ready"] or status == "locked" and i == world.chapter_index
	for o in ch.get("objectives", []):
		var p := ChapterRules.objective_progress(world, fid, o)
		if status == "done":
			p["done"] = true
			p["current"] = p["target"]
		box.add_child(_objective_row(String(o.get("text", "")), p, live or status == "done",
			String(o.get("type", "")) in ["income", "collected_total"]))
	var need := int(ch.get("unlock", {}).get("family_power", 0))
	if need > 0:
		var have := world.faction_power(fid)
		box.add_child(UiTheme.label("Unlocks at %d family power  (you have %d)" % [need, have], 17,
			UiTheme.GREEN if have >= need else UiTheme.MUTED, "body_medium"))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	box.add_child(foot)
	var rw := HBoxContainer.new()
	rw.add_theme_constant_override("separation", 8)
	rw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(rw)
	rw.add_child(UiTheme.label("REWARD", 16, UiTheme.MUTED, "caps"))
	rw.add_child(UiTheme.icon_rect("cash", 24, UiTheme.GOLD))
	rw.add_child(UiTheme.label(UiTheme.money(int(ch.get("rewards", {}).get("cash", 0))), 24, UiKit.IVORY, "body_bold"))
	if status == "ready":
		var b := UiKit.button("Claim reward", "primary", "", 240)
		b.pressed.connect(claim)
		foot.add_child(b)


static func _objective_row(text: String, p: Dictionary, show_progress: bool, is_money: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var mark := UiTheme.dot(UiTheme.GREEN if p["done"] else Color(UiTheme.GOLD, 0.5), 10)
	h.add_child(mark)
	var l := UiTheme.label(text, 20, UiKit.IVORY if not p["done"] else UiTheme.MUTED, "body_medium")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if show_progress:
		var cur: int = p["current"]
		var tgt: int = p["target"]
		h.add_child(UiTheme.label(progress_text(mini(cur, tgt), tgt, is_money), 17, UiTheme.MUTED, "body_bold"))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 5)
		bar.max_value = maxi(tgt, 1)
		bar.value = mini(cur, tgt)
		v.add_child(bar)
	return v


static func progress_text(cur: int, tgt: int, is_money: bool) -> String:
	if is_money:
		return "%s / %s" % [UiTheme.short_money(cur), UiTheme.short_money(tgt)]
	return "%d / %d" % [cur, tgt]
