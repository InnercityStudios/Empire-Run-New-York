extends SceneTree
## Renders a top-down map of the world layout to docs/world_map.png
## (regions, roads, park, piers, bridge, landmarks). Development aid.
## Usage: Godot --headless --path . -s tests/tools_world_map.gd

const SCALE := 0.25  # pixels per metre
const STYLE_COLORS := {
	"tenement": Color("#8a4b3a"), "industrial": Color("#6b6560"), "rowhouse": Color("#7a5a44"),
	"towers": Color("#9a8f7c"), "civic": Color("#8f7a66"), "suburban": Color("#7d9a5e"),
	"waterfront": Color("#7c7f86"), "park": Color("#4f7a3a"),
}

func _initialize() -> void:
	var c := GameContent.load_default()
	var w := WorldLayout.build(c.worlds["greater_new_york"], c)
	var r := w.world_rect
	var img := Image.create(int(r.size.x * SCALE), int(r.size.y * SCALE), false, Image.FORMAT_RGBA8)
	img.fill(Color("#1f3a44"))
	var to_px := func(p: Vector2) -> Vector2i: return Vector2i(((p - r.position) * SCALE).round())
	var fill := func(rect: Rect2, col: Color) -> void:
		var a: Vector2i = to_px.call(rect.position)
		var b: Vector2i = to_px.call(rect.end)
		img.fill_rect(Rect2i(a, b - a), col)
	fill.call(w.land, Color("#3a3836"))
	for bd in w.backdrops:
		fill.call(bd["rect"], Color("#34322f"))
		for box in bd["boxes"]:
			fill.call(box["rect"], Color("#4a4440"))
	for b in w.blocks:
		fill.call(b["rect"], STYLE_COLORS.get(b["style"], Color.GRAY).darkened(0.25))
	for lot in w.lots:
		var t: Transform3D = lot["transform"]
		var def: Dictionary = c.building_catalog[lot["building"]]
		var p: Vector2 = Vector2(t.origin.x, t.origin.z) - Vector2(t.basis.z.x, t.basis.z.z) * float(def.get("depth", 20.0)) * 0.5
		var s: float = maxf(def["width"], 4.0) * 0.5
		fill.call(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), STYLE_COLORS.get(w.region_at(p).get("style", ""), Color.GRAY))
	for pk in w.parks:
		fill.call(pk["lake"], Color("#2a5560"))
		for t in pk["trees"]:
			fill.call(Rect2(t - Vector2(2, 2), Vector2(4, 4)), Color("#2f5a2a"))
	for pr in w.piers:
		fill.call(pr["deck"], Color("#8d8a82"))
	for seg in w.road_segments:
		var a: Vector2 = seg["from"]
		var b: Vector2 = seg["to"]
		var hw: float = seg["width"] * 0.5
		fill.call(Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(hw, hw) * Vector2(absf(b.y - a.y) > 0.1, absf(b.x - a.x) > 0.1),
			Vector2(absf(b.x - a.x), absf(b.y - a.y)) + Vector2(hw * 2, hw * 2) * Vector2(absf(b.y - a.y) > 0.1, absf(b.x - a.x) > 0.1)),
			Color("#c9a24a") if seg["width"] >= 18 else Color("#d8d2c4"))
	for id in w.landmarks:
		var f: Vector2 = w.landmarks[id]["frontage"]
		fill.call(Rect2(f - Vector2(12, 12), Vector2(24, 24)), Color("#e8c97f"))
	img.save_png("res://docs/world_map.png")
	print("WORLD MAP %dx%d px, %.1f x %.1f km land" % [img.get_width(), img.get_height(), w.land.size.x / 1000.0, w.land.size.y / 1000.0])
	quit()
