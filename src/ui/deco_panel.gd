class_name DecoPanel
extends PanelContainer
## Panel with art-deco corner brackets and an inner hairline, the frame used
## by every floating card in the interface.

@export var ornament_color := UiTheme.GOLD
@export var inset := 7.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-inset)
	var c := Color(ornament_color, 0.55)
	draw_rect(r, c, false, 1.0)
	var arm := minf(28.0, minf(r.size.x, r.size.y) * 0.3)
	var gold := ornament_color
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x < r.get_center().x else -1.0
		var sy := 1.0 if corner.y < r.get_center().y else -1.0
		draw_line(corner, corner + Vector2(arm * sx, 0), gold, 2.0)
		draw_line(corner, corner + Vector2(0, arm * sy), gold, 2.0)
		var d: Vector2 = corner + Vector2(10 * sx, 10 * sy)
		draw_colored_polygon(PackedVector2Array([d + Vector2(0, -4), d + Vector2(4, 0), d + Vector2(0, 4), d + Vector2(-4, 0)]), gold)
