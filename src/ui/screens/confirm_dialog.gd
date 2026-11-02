class_name ConfirmDialog
extends RefCounted
## Two-button confirmation modal (Back closes it).


static func ask(parent: Node, title: String, message: String, confirm_text: String, on_confirm: Callable,
		danger := false) -> void:
	var m := UiKit.modal(parent, 620.0, title)
	var body: VBoxContainer = m["body"]
	var msg := UiTheme.label(message, 19, UiKit.IVORY, "body_medium")
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(msg)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	var root: Control = m["root"]
	var back := func() -> bool:
		UiKit.close_modal(root)
		return true
	App.push_back(back)
	root.tree_exiting.connect(func(): App.pop_back(back))
	var cancel := UiKit.button("Cancel", "secondary", "", 180)
	cancel.pressed.connect(func(): UiKit.close_modal(root))
	row.add_child(cancel)
	var ok := UiKit.button(confirm_text, "danger" if danger else "primary", "", 180)
	ok.pressed.connect(func():
		UiKit.close_modal(root)
		on_confirm.call())
	row.add_child(ok)
	(m["dim"] as ColorRect).gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			UiKit.close_modal(root))
