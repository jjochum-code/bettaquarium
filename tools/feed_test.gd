extends SceneTree
## Drops pellets on a schedule and logs every change of the feeding state.
## Usage: godot --path . -s tools/feed_test.gd [--headless]

const Betta := preload("res://betta.gd")

const DROP_TIMES := [1.0, 12.0, 12.4]
const DURATION := 12.0

var _main: Node
var _time := 0.0
var _drops := DROP_TIMES.duplicate()
var _last_state := ""


func _init() -> void:
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(_main)


func _process(delta: float) -> bool:
	_time += delta
	while not _drops.is_empty() and _time >= _drops[0]:
		_drops.pop_front()
		_main._drop_food()
		print("%.1f drop" % _time)

	var fish: Betta = _main._fish
	var food := fish._nearest_food()
	var mouth := fish.to_global(Betta.MOUTH)
	var state := "%s/%s" % [Betta.State.keys()[fish._state], Betta.Feed.keys()[fish._feed]]
	if state != _last_state:
		var dist := mouth.distance_to(food.position) if food else -1.0
		print("%.2f %s mouth-pellet=%.3f speed=%.2f" % [_time, state, dist, fish._speed])
		_last_state = state

	var half_second := int(_time * 2.0) != int((_time - delta) * 2.0)
	if fish._state == Betta.State.FEED and food and half_second:
		var to_food := food.position - mouth
		print("   %.1f d=%.3f ang=%.2f centre=%.2f pitch=%.2f speed=%.2f pellet=%s" % [
			_time, to_food.length(), (-fish.basis.z).angle_to(to_food),
			food.position.distance_to(fish.position), fish._pitch, fish._speed, food.position])
	return _time > DURATION
