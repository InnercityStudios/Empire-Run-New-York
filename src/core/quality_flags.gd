class_name QualityFlags
extends RefCounted
## Development switches for profiling rendering features in isolation, passed
## as user arguments after "--" (e.g. --no-probe). Shipping builds use defaults.

static func off(feature: String) -> bool:
	return ("--no-" + feature) in OS.get_cmdline_user_args()
