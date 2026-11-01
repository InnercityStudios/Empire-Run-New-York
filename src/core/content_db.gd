extends Node
## Autoload "Content": the game's single loaded GameContent instance.

var db: GameContent


func _init() -> void:
	db = GameContent.load_default()
