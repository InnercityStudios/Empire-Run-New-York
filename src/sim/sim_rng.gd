class_name SimRng
extends RefCounted
## Deterministic 32-bit xorshift RNG. Identical sequences on every platform,
## so server and client agree on AI decisions and future combat rolls.

const MASK := 0xFFFFFFFF

var state: int = 0x9E3779B9


func _init(seed_value: int = 0x9E3779B9) -> void:
	state = seed_value & MASK
	if state == 0:
		state = 0x9E3779B9


func next_u32() -> int:
	var x := state
	x ^= (x << 13) & MASK
	x ^= x >> 17
	x ^= (x << 5) & MASK
	state = x & MASK
	return state


## Integer in [0, n).
func range_int(n: int) -> int:
	if n <= 0:
		return 0
	return next_u32() % n


## True with probability permille / 1000.
func chance_permille(permille: int) -> bool:
	return range_int(1000) < permille
