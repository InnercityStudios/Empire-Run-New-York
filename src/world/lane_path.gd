class_name LanePath
extends RefCounted
## Drivable path in the right-hand lane: the street centreline polyline offset
## to the right with rounded corners, sampled by arc length.

const CORNER_RADIUS := 6.0
const CORNER_STEPS := 6

var points := PackedVector2Array()
var cumulative := PackedFloat32Array()
var length := 0.0


static func from_centreline(centre: Array, lane_offset: float) -> LanePath:
	var lp := LanePath.new()
	var c: Array = []
	for p in centre:
		if c.is_empty() or (c[-1] as Vector2).distance_to(p) > 0.05:
			c.append(p)
	if c.size() == 1:
		lp._add(c[0])
		lp._finish()
		return lp
	var dirs: Array = []
	for i in c.size() - 1:
		dirs.append(((c[i + 1] as Vector2) - c[i]).normalized())
	lp._add(c[0] + _right(dirs[0]) * lane_offset)
	for i in range(1, c.size() - 1):
		var d0: Vector2 = dirs[i - 1]
		var d1: Vector2 = dirs[i]
		var p: Vector2 = c[i]
		if d0.dot(d1) > 0.999:
			continue
		if d0.dot(d1) < -0.9:
			# U-turn: swing across the carriageway.
			lp._add(p + _right(d0) * lane_offset)
			lp._add(p + _right(d1) * lane_offset)
			continue
		# Miter point of the two offset lines, then a quadratic bezier corner.
		var a0: Vector2 = p + _right(d0) * lane_offset
		var a1: Vector2 = p + _right(d1) * lane_offset
		var denom := d0.cross(d1)
		var m := a0
		if absf(denom) > 1e-4:
			m = a0 + d0 * ((a1 - a0).cross(d1) / denom)
		var len0 := (p - (c[i - 1] as Vector2)).length() * 0.5
		var len1 := ((c[i + 1] as Vector2) - p).length() * 0.5
		var r := minf(CORNER_RADIUS, minf(len0, len1))
		var s := m - d0 * r
		var e := m + d1 * r
		for k in CORNER_STEPS + 1:
			var t := float(k) / CORNER_STEPS
			lp._add(s.lerp(m, t).lerp(m.lerp(e, t), t))
	lp._add((c[-1] as Vector2) + _right(dirs[-1]) * lane_offset)
	lp._finish()
	return lp


static func _right(d: Vector2) -> Vector2:
	# Ground plane (x, z) with +Y up: right of the travel direction.
	return Vector2(-d.y, d.x)


func _add(p: Vector2) -> void:
	if points.size() > 0 and points[-1].distance_to(p) < 0.01:
		return
	points.append(p)


func _finish() -> void:
	cumulative.resize(points.size())
	length = 0.0
	for i in points.size():
		if i > 0:
			length += points[i].distance_to(points[i - 1])
		cumulative[i] = length


## {pos: Vector2, dir: Vector2} at arc length s.
func sample(s: float) -> Dictionary:
	if points.size() == 1:
		return {"pos": points[0], "dir": Vector2(0, -1)}
	s = clampf(s, 0.0, length)
	var lo := 0
	var hi := points.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cumulative[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := maxf(cumulative[hi] - cumulative[lo], 0.0001)
	var t := (s - cumulative[lo]) / seg
	return {"pos": points[lo].lerp(points[hi], t), "dir": (points[hi] - points[lo]).normalized()}
