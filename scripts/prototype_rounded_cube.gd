extends AnimatableBody3D

## Grid-based rolling cube: each WASD press tips it over the bottom edge facing
## the input, so moving and rotating are one motion. Rolls are scripted rather
## than physics-driven, which keeps the cube landing on whole grid cells; the
## physics world is only queried, for ground under the cube and for blocked
## cells ahead of it.

## World-space size of one cube edge.
@export var cube_size: float = 1.0
## Seconds a single 90 degree roll takes.
@export var roll_duration: float = 0.15
## Downward acceleration while falling. Higher than real gravity on purpose:
## puzzle drops read better when they are snappy.
@export var gravity: float = 20.0
## Physics layers that count as solid ground and as blocking walls.
@export_flags_3d_physics var collision_mask_world: int = 1
## Camera that rides along with the cube without tumbling with it.
## Left empty, the first Camera3D below this node is used.
@export var camera: Camera3D

var _camera_offset: Vector3 = Vector3.ZERO
var _rolling: bool = false
var _falling: bool = false
var _fall_speed: float = 0.0
var _elapsed: float = 0.0
var _axis: Vector3 = Vector3.RIGHT
var _pivot: Vector3 = Vector3.ZERO
var _start_transform: Transform3D = Transform3D.IDENTITY
var _end_transform: Transform3D = Transform3D.IDENTITY
var _cell_query: PhysicsShapeQueryParameters3D


func _ready() -> void:
	_build_cell_query()
	if camera == null:
		var found := find_children("", "Camera3D", true, false)
		if not found.is_empty():
			camera = found[0]
	if camera == null:
		return
	# Keep the camera where the scene placed it, but cut it loose from this
	# node's transform so the roll's rotation and scale never reach it.
	var camera_global := camera.global_transform
	_camera_offset = camera_global.origin - global_position
	camera.top_level = true
	camera.global_transform = camera_global


func _process(delta: float) -> void:
	# Falling beats rolling beats input: without that order a roll could start
	# off the edge of a ledge and animate through mid-air.
	if _falling:
		_fall(delta)
	elif _rolling:
		_advance_roll(delta)
	elif not _has_ground():
		_falling = true
		_fall_speed = 0.0
	else:
		var dir := _read_direction()
		if dir != Vector3.ZERO and not _cell_is_blocked(dir):
			_start_roll(dir)
	if camera != null:
		# Only the position is handed over; the camera keeps its own orientation.
		camera.global_position = global_position + _camera_offset


## Returns the pressed direction in parent space, or ZERO when idle.
## Physical keycodes are used so the keys stay in the same spot on any layout.
func _read_direction() -> Vector3:
	if Input.is_physical_key_pressed(KEY_W) || Input.is_physical_key_pressed(KEY_UP):
		return Vector3.FORWARD
	if Input.is_physical_key_pressed(KEY_S) || Input.is_physical_key_pressed(KEY_DOWN):
		return Vector3.BACK
	if Input.is_physical_key_pressed(KEY_A) || Input.is_physical_key_pressed(KEY_LEFT):
		return Vector3.LEFT
	if Input.is_physical_key_pressed(KEY_D) || Input.is_physical_key_pressed(KEY_RIGHT):
		return Vector3.RIGHT
	return Vector3.ZERO


func _start_roll(dir: Vector3) -> void:
	var half := cube_size * 0.5
	# Tip over the bottom edge on the side we are heading towards.
	_pivot = position + dir * half + Vector3.DOWN * half
	_axis = Vector3.UP.cross(dir)
	_start_transform = transform
	_end_transform = _rotated_around_pivot(_start_transform, PI * 0.5)
	# Land exactly on the grid so repeated rolls cannot accumulate drift.
	_end_transform.origin = _end_transform.origin.snapped(Vector3.ONE * cube_size * 0.5)
	_elapsed = 0.0
	_rolling = true


func _advance_roll(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= roll_duration:
		transform = _end_transform
		_rolling = false
		return
	transform = _rotated_around_pivot(_start_transform, PI * 0.5 * (_elapsed / roll_duration))


## Rotates a transform about the pivot edge, keeping its scale intact.
func _rotated_around_pivot(from: Transform3D, angle: float) -> Transform3D:
	var rotation_basis := Basis(_axis, angle)
	var result := from
	result.basis = rotation_basis * from.basis
	result.origin = _pivot + rotation_basis * (from.origin - _pivot)
	return result


func _fall(delta: float) -> void:
	_fall_speed += gravity * delta
	var step := _fall_speed * delta
	# Look a whole step ahead so a fast fall cannot tunnel through the floor.
	var hit := _ray_down(cube_size * 0.5 + step)
	if hit.is_empty():
		global_position.y -= step
		return
	# Settle on top of whatever we landed on, back on the grid.
	global_position.y = hit.position.y + cube_size * 0.5
	_fall_speed = 0.0
	_falling = false


func _has_ground() -> bool:
	return not _ray_down(cube_size * 0.5 + 0.05).is_empty()


## Casts from the cube's centre straight down and returns the hit, if any.
func _ray_down(length: float) -> Dictionary:
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * length)
	query.collision_mask = collision_mask_world
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


## True when something solid already occupies the cell we would roll into.
func _cell_is_blocked(dir: Vector3) -> bool:
	_cell_query.transform = Transform3D(Basis(), global_position + dir * cube_size)
	return not get_world_3d().direct_space_state.intersect_shape(_cell_query, 1).is_empty()


func _build_cell_query() -> void:
	var shape := BoxShape3D.new()
	# Shrunk slightly so the probe cannot graze the neighbours of the target cell.
	shape.size = Vector3.ONE * cube_size * 0.9
	_cell_query = PhysicsShapeQueryParameters3D.new()
	_cell_query.shape = shape
	_cell_query.collision_mask = collision_mask_world
	_cell_query.exclude = [get_rid()]
