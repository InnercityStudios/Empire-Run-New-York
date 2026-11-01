class_name LayoutFingerprint
extends RefCounted
## Stable hash of a layout's building lots (ids and rounded transforms), used
## to prove refactors keep existing building identities and placements.


static func of(layout: DistrictLayout) -> String:
	var parts := PackedStringArray()
	for lot in layout.lots:
		var t: Transform3D = lot["transform"]
		parts.append("%s@%.2f,%.2f,%.2f/%.3f,%.3f" % [lot["building"], t.origin.x, t.origin.y, t.origin.z, t.basis.x.x, t.basis.z.z])
	return "%d:%s" % [layout.lots.size(), "|".join(parts).sha256_text().substr(0, 16)]
