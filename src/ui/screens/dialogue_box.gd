class_name DialogueBox
extends Control
## Conversation overlay for data/dialogue/<id>.json: portrait slot, speaker
## name, typed subtitles, Next / Skip / Auto. Voice-ready: a line plays
## assets/audio/dialogue/<line id>.(ogg|mp3|wav) on the Dialogue bus when that
## file exists (e.g. ElevenLabs exports), and Auto waits for it to finish.
## Portraits are a monogram until character art is approved.

signal finished

const DIALOGUE_DIR := "res://data/dialogue/"
const VOICE_DIR := "res://assets/audio/dialogue/"
const CHARS_PER_SECOND := 45.0
const AUTO_HOLD := 1.6

var _lines: Array = []
var _index := -1
var _speaker: Label
var _text: Label
var _portrait: Control
var _auto_button: Button
var _type_tween: Tween
var _auto_timer: Timer
var _voice: AudioStreamPlayer
var _back := Callable()


## Opens a conversation by id; returns null when the file is missing or empty.
static func play(parent: Node, dialogue_id: String) -> DialogueBox:
	var path := DIALOGUE_DIR + dialogue_id + ".json"
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or (parsed.get("lines", []) as Array).is_empty():
		return null
	var box := DialogueBox.new()
	box._lines = parsed["lines"]
	parent.add_child(box)
	return box


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := TextureRect.new()
	var g := GradientTexture2D.new()
	g.fill_from = Vector2(0.5, 0)
	g.fill_to = Vector2(0.5, 1)
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.02, 0.018, 0.016, 0.85)])
	g.gradient = gr
	shade.texture = g
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -420
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var m := UiKit.safe_margins(self)
	var p := UiKit.panel(14, 0.45, 24)
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.custom_minimum_size = Vector2(1300, 230)
	p.offset_left = -650
	p.offset_right = 650
	p.offset_bottom = -m.w - 24
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	p.add_child(h)
	_portrait = Control.new()
	_portrait.custom_minimum_size = Vector2(170, 170)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_portrait)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_speaker = UiTheme.label("", 28, UiTheme.GOLD_LIGHT, "display")
	v.add_child(_speaker)
	_text = UiTheme.label("", 25, UiKit.IVORY, "body_medium")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(0, 100)
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	_auto_button = UiKit.button("Auto", "secondary", "", 130)
	_auto_button.toggle_mode = true
	_auto_button.button_pressed = bool(App.get_setting("gameplay", "dialogue_auto"))
	_auto_button.toggled.connect(func(on: bool):
		App.set_setting("gameplay", "dialogue_auto", on)
		if on and not _typing():
			_schedule_auto())
	row.add_child(_auto_button)
	var skip := UiKit.button("Skip", "secondary", "", 130)
	skip.pressed.connect(_close)
	row.add_child(skip)
	var next := UiKit.button("Next", "primary", "chevron", 160)
	next.pressed.connect(advance)
	row.add_child(next)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Dialogue"
	_voice.finished.connect(func():
		if _auto_button.button_pressed:
			_schedule_auto())
	add_child(_voice)
	_auto_timer = Timer.new()
	_auto_timer.one_shot = true
	_auto_timer.timeout.connect(advance)
	add_child(_auto_timer)
	_back = func() -> bool:
		_close()
		return true
	App.push_back(_back)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)
	advance()


func _exit_tree() -> void:
	App.pop_back(_back)


func _gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
			or (e is InputEventScreenTouch and e.pressed):
		advance()


## Tap: finish the typing first, then move to the next line.
func advance() -> void:
	_auto_timer.stop()
	if _typing():
		_type_tween.kill()
		_text.visible_ratio = 1.0
		_on_typed()
		return
	_index += 1
	if _index >= _lines.size():
		_close()
		return
	var line: Dictionary = _lines[_index]
	var speaker := tr(String(line.get("speaker", "")))
	_speaker.text = speaker
	_text.text = tr(String(line.get("text", "")))
	_text.visible_ratio = 0.0
	_set_portrait(speaker, String(line.get("portrait", "")))
	_type_tween = create_tween()
	_type_tween.tween_property(_text, "visible_ratio", 1.0, _text.text.length() / CHARS_PER_SECOND)
	_type_tween.finished.connect(_on_typed)
	_voice.stop()
	var stream := _voice_for(String(line.get("id", "")))
	if stream:
		_voice.stream = stream
		_voice.play()


func _typing() -> bool:
	return _type_tween != null and _type_tween.is_running()


func _on_typed() -> void:
	if _auto_button.button_pressed and not _voice.playing:
		_schedule_auto()


func _schedule_auto() -> void:
	_auto_timer.start(AUTO_HOLD + _text.text.length() / 90.0)


static func _voice_for(line_id: String) -> AudioStream:
	if line_id == "":
		return null
	for ext: String in ["ogg", "mp3", "wav"]:
		var path := VOICE_DIR + line_id + "." + ext
		if ResourceLoader.exists(path):
			return load(path)
	return null


func _set_portrait(speaker: String, portrait: String) -> void:
	for c in _portrait.get_children():
		c.queue_free()
	if portrait != "" and ResourceLoader.exists(portrait):
		var t := TextureRect.new()
		t.texture = load(portrait)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		_portrait.add_child(t)
		return
	# No approved character art yet: a neutral monogram seal.
	_portrait.add_child(UiKit.crest("seal", UiKit.initials_for(speaker), UiTheme.GOLD_DARK, 170))


func _close() -> void:
	if is_queued_for_deletion() or mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_auto_timer.stop()
	_voice.stop()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		finished.emit()
		queue_free())
