class_name AmbienceDirector
extends Node
## City soundscape, layered by camera height:
## - bed: continuous traffic loop, louder near street level;
## - events: an occasional siren pass (exposed for future police heat);
## - spatial: car horns from passing traffic, only when zoomed in close.

const BED := preload("res://assets/audio/ambience/city_traffic.wav")
const SIRENS := preload("res://assets/audio/events/street_sirens.mp3")
const HORN := preload("res://assets/audio/sfx/vehicles/car_horn.mp3")
const SIREN_INTERVAL := Vector2(90.0, 240.0)
const HORN_INTERVAL := Vector2(9.0, 26.0)
const HORN_MAX_DISTANCE := 260.0

var camera: StrategyCamera
var traffic: TrafficSystem
var _bed: AudioStreamPlayer
var _sirens: AudioStreamPlayer
var _horn: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _next_siren := 0.0
var _next_horn := 0.0
var _distance := 150.0


func _ready() -> void:
	_rng.randomize()
	_bed = AudioStreamPlayer.new()
	_bed.stream = BED
	_bed.volume_db = -14.0
	_bed.autoplay = true
	_bed.bus = "Ambience"
	add_child(_bed)
	_sirens = AudioStreamPlayer.new()
	_sirens.stream = SIRENS
	_sirens.bus = "SFX"
	add_child(_sirens)
	_horn = AudioStreamPlayer3D.new()
	_horn.stream = HORN
	_horn.unit_size = 18.0
	_horn.max_distance = 400.0
	_horn.volume_db = -6.0
	_horn.bus = "SFX"
	add_child(_horn)
	_next_siren = _rng.randf_range(SIREN_INTERVAL.x * 0.4, SIREN_INTERVAL.y * 0.6)
	_next_horn = _rng.randf_range(HORN_INTERVAL.x, HORN_INTERVAL.y)


func on_camera_distance(d: float) -> void:
	_distance = d
	# Street noise fades as the camera climbs to the strategic view.
	_bed.volume_db = lerpf(-9.0, -27.0, clampf((d - 60.0) / 520.0, 0.0, 1.0))


## Play a siren pass now (police response, raids, story beats).
func play_sirens(volume_db := -12.0) -> void:
	_sirens.volume_db = volume_db + lerpf(0.0, -12.0, clampf((_distance - 80.0) / 500.0, 0.0, 1.0))
	_sirens.play()


func _process(delta: float) -> void:
	_next_siren -= delta
	if _next_siren <= 0.0:
		_next_siren = _rng.randf_range(SIREN_INTERVAL.x, SIREN_INTERVAL.y)
		play_sirens(-16.0)
	_next_horn -= delta
	if _next_horn <= 0.0:
		_next_horn = _rng.randf_range(HORN_INTERVAL.x, HORN_INTERVAL.y)
		if _distance < HORN_MAX_DISTANCE and traffic and not _horn.playing:
			var p: Variant = traffic.random_car_position()
			if p != null:
				_horn.global_position = p
				_horn.pitch_scale = _rng.randf_range(0.92, 1.08)
				_horn.play()
