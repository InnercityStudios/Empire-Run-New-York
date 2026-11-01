extends SceneTree
## Headless test runner.
## Usage: Godot --headless --path . -s tests/run_tests.gd
## Runs every test_* method of every tests/test_*.gd script; exits non-zero on failure.

var _failures := 0
var _passes := 0


const TIMEOUT_MS := 120_000


func _initialize() -> void:
	# Watchdog: never hang CI if a test script fails to compile or loops.
	var start := Time.get_ticks_msec()
	create_timer(TIMEOUT_MS / 1000.0).timeout.connect(func():
		print("TESTS: timed out after %d ms" % (Time.get_ticks_msec() - start))
		quit(2))
	_run.call_deferred()


func _run() -> void:
	var dir := DirAccess.open("res://tests")
	var files: Array = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			_failures += 1
			print("  FAIL %s: script does not compile" % f)
			continue
		var suite: Object = script.new()
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			if suite.has_method("before_each"):
				suite.call("before_each")
			suite.set("failures", [])
			suite.call(mname)
			var fails: Array = suite.get("failures")
			if fails.is_empty():
				_passes += 1
				print("  PASS %s.%s" % [f.get_basename(), mname])
			else:
				_failures += 1
				for msg in fails:
					print("  FAIL %s.%s: %s" % [f.get_basename(), mname, msg])
	print("TESTS: %d passed, %d failed" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)
