extends SceneTree
## Prints the Little Italy layout fingerprint used by test_world.gd's
## preservation test. Run once before layout refactors.

func _initialize() -> void:
	var c := GameContent.load_default()
	var l := DistrictLayout.build(c.districts["little_italy"], c.building_catalog)
	print("FINGERPRINT ", LayoutFingerprint.of(l))
	quit()
