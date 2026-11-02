class_name SettingsPanel
extends RefCounted
## Settings overlay: Audio, Graphics, Gameplay and Account tabs. Every change
## goes through App.set_setting (persisted and applied immediately).

const TABS := ["Audio", "Graphics", "Gameplay", "Account"]
const QUALITY := ["low", "medium", "high"]
const FPS := [30, 60]


static func open(parent: Node, tab := 0) -> Control:
	var m := UiKit.overlay(parent, 1060.0, "Settings")
	var body: VBoxContainer = m["body"]
	var tabs_row := HBoxContainer.new()
	tabs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(tabs_row)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	page.custom_minimum_size = Vector2(0, 470)
	var page_margin := MarginContainer.new()
	page_margin.add_theme_constant_override("margin_left", 40)
	page_margin.add_theme_constant_override("margin_right", 40)
	page_margin.add_theme_constant_override("margin_top", 12)
	page_margin.add_child(page)
	body.add_child(page_margin)
	var show := func(i: int) -> void:
		for c in page.get_children():
			c.queue_free()
		match i:
			0:
				_audio(page)
			1:
				_graphics(page)
			2:
				_gameplay(page)
			3:
				_account(page, m["root"])
	tabs_row.add_child(UiKit.segmented(TABS, tab, show))
	show.call(tab)
	return m["root"]


static func _section(page: Control, text: String) -> void:
	page.add_child(UiTheme.caption(text, UiTheme.GOLD))


static func _audio(page: Control) -> void:
	_section(page, "Volume")
	for row in [["Master", "master"], ["Music", "music"], ["Sound effects", "sfx"], ["City ambience", "ambience"],
			["Dialogue", "dialogue"]]:
		var key: String = row[1]
		page.add_child(UiKit.slider_row(row[0], float(App.get_setting("audio", key)),
			func(v: float): App.set_setting("audio", key, v)))


static func _graphics(page: Control) -> void:
	_section(page, "Graphics quality")
	var q := QUALITY.find(String(App.get_setting("graphics", "quality")))
	page.add_child(UiKit.segmented(["Low", "Medium", "High"], maxi(q, 0),
		func(i: int): App.set_setting("graphics", "quality", QUALITY[i])))
	page.add_child(_note("Low renders at reduced resolution without shadows to save battery and heat. "
		+ "High is the intended presentation."))
	_section(page, "Frame rate")
	page.add_child(UiKit.segmented(["30 FPS", "60 FPS"], maxi(FPS.find(int(App.get_setting("graphics", "fps"))), 0),
		func(i: int): App.set_setting("graphics", "fps", FPS[i])))
	page.add_child(_note("30 FPS extends battery life on phones."))


static func _gameplay(page: Control) -> void:
	_section(page, "Controls and feedback")
	page.add_child(UiKit.toggle_row("Vibration", "Light haptic feedback on taps (phones only).",
		bool(App.get_setting("gameplay", "haptics")), func(on: bool): App.set_setting("gameplay", "haptics", on)))
	page.add_child(UiKit.toggle_row("Loading tips", "Show gameplay tips while the city loads.",
		bool(App.get_setting("gameplay", "tips")), func(on: bool): App.set_setting("gameplay", "tips", on)))
	page.add_child(UiKit.toggle_row("Auto-advance dialogue", "Conversations continue on their own after each line.",
		bool(App.get_setting("gameplay", "dialogue_auto")),
		func(on: bool): App.set_setting("gameplay", "dialogue_auto", on)))
	_section(page, "Language")
	page.add_child(UiKit.segmented(["English"], 0, func(_i: int): pass))
	page.add_child(_note("Further languages will be added with localisation."))


static func _account(page: Control, overlay_root: Control) -> void:
	_section(page, "Account")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	page.add_child(h)
	if App.has_profile():
		var p := App.profile
		h.add_child(UiKit.crest(p.get("crest", "shield"), UiKit.initials_for(p.get("username", "")),
			Color(p.get("family_color", "#c9a24a")), 72))
		var v := VBoxContainer.new()
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		v.add_child(UiTheme.label(String(p.get("username", "")), 24, UiKit.IVORY, "display"))
		v.add_child(UiTheme.label("%s Family  ·  local profile on this device" % p.get("family_name", ""), 16,
			UiTheme.MUTED, "body_medium"))
		h.add_child(v)
	else:
		h.add_child(UiTheme.label("No profile yet. Start a new game to create one.", 18, UiKit.IVORY, "body_medium"))
	var notice := UiKit.panel(10, 0.25, 16)
	page.add_child(notice)
	var nl := UiTheme.label("Online accounts and cloud saves are not available yet. Progress is stored only on this "
		+ "device and is lost if the game is uninstalled.", 16, UiTheme.MUTED, "body_medium")
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_child(nl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	page.add_child(row)
	var link := UiKit.button("Sign in", "secondary", "", 200)
	link.disabled = true
	link.tooltip_text = "Online accounts are not available yet."
	row.add_child(link)
	var reset := UiKit.button("Reset local progress", "danger", "", 260)
	reset.disabled = not (App.has_profile() or App.save_exists())
	reset.pressed.connect(func():
		ConfirmDialog.ask(overlay_root.get_parent(), "Reset local progress?",
			"Your profile and saved game on this device will be deleted. This cannot be undone.", "Reset",
			func(): App.reset_local_progress(), true))
	row.add_child(reset)


static func _note(text: String) -> Label:
	var l := UiTheme.label(text, 15, UiTheme.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
