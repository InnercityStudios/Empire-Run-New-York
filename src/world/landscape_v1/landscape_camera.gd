extends Camera3D
## Landscape-only inspection camera. Does not read or modify gameplay state.
var focus := Vector3(13500, 0, -12000)
var span := 29000.0
var angled := false
var dragging := false

func _ready() -> void:
 make_current()
 _place()
 var terrain := get_parent().get_node("Terrain3D") as Terrain3D
 terrain.set_camera(self)
 var layer := CanvasLayer.new()
 add_child(layer)
 var panel := PanelContainer.new()
 panel.position = Vector2(24,24)
 layer.add_child(panel)
 var margin := MarginContainer.new()
 for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,16)
 panel.add_child(margin)
 var box := VBoxContainer.new()
 box.add_theme_constant_override("separation",8)
 margin.add_child(box)
 var title := Label.new()
 title.text = "EMPIRE: RUN NEW YORK  /  LANDSCAPE"
 title.add_theme_font_size_override("font_size",22)
 box.add_child(title)
 var info := Label.new()
 info.text = "27 × 24 km • 4 m height samples • sea level 0 m"
 box.add_child(info)
 var row := HBoxContainer.new()
 row.add_theme_constant_override("separation",8)
 box.add_child(row)
 for preset in ["World","Angled","Manhattan","Estate pond"]:
  var b := Button.new()
  b.text = preset
  b.pressed.connect(_preset.bind(preset))
  row.add_child(b)
 var hint := Label.new()
 hint.text = "Scroll: zoom   ·   Right/middle drag: pan   ·   WASD/arrows: move   ·   Home: world"
 hint.add_theme_font_size_override("font_size",14)
 box.add_child(hint)
 print("Landscape: loaded ", terrain.data.get_region_count(), " regions; height range ",terrain.data.get_height_range())
 for sample in [Vector3(8650,0,-9600),Vector3(23200,0,-8600),Vector3(6000,0,-10000)]:
  print("Landscape sample ", sample, " height=",terrain.data.get_height(sample))

func _preset(which: String) -> void:
 angled = which == "Angled"
 if which in ["World","Angled"]:
  focus=Vector3(13500,0,-12000); span=29000
 elif which == "Manhattan":
  focus=Vector3(8650,0,-9600); span=4300
 else:
  focus=Vector3(23200,0,-8600); span=3800; angled=true
 _place()

func _place() -> void:
 projection = Camera3D.PROJECTION_ORTHOGONAL
 keep_aspect = Camera3D.KEEP_WIDTH
 size = span * 1.15
 near = .5
 far = 100000
 if angled:
  position=focus+Vector3(0,span*.85,span*.58)
  look_at(focus,Vector3.UP)
 else:
  position=focus+Vector3(0,span,0)
  rotation_degrees=Vector3(-90,0,0)

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseButton:
  if event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]: dragging=event.pressed
  if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
   span=clampf(span*(.82 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.22),180,36000)
   _place()
 if event is InputEventMouseMotion and dragging:
  var scale_m := size / get_viewport().get_visible_rect().size.x
  focus+=Vector3(-event.relative.x*scale_m,0,-event.relative.y*scale_m)
  _place()
 if event is InputEventKey and event.pressed:
  if event.keycode==KEY_HOME: _preset("World")
  if event.keycode==KEY_TAB: angled=not angled; _place()

func _process(delta: float) -> void:
 var direction:=Vector3.ZERO
 if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): direction.z-=1
 if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): direction.z+=1
 if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): direction.x-=1
 if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): direction.x+=1
 if direction!=Vector3.ZERO:
  focus+=direction.normalized()*span*.45*delta
  _place()
