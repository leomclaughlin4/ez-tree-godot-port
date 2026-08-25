@tool
@icon("res://addons/ez-tree-godot-port/ez_tree_icon.svg")
class_name EZTreeDraw
extends Node3D
## Paint EZTree trees onto ground geometry directly in the editor viewport.
##
## Setup:
##   1. Add an EZTreeDraw node to your scene.
##   2. Add an EZTree node as a CHILD of it — this is the template tree.
##      Tweak it until you like the look (you can hide it afterwards).
##   3. Make sure your ground MeshInstance3D has a StaticBody3D +
##      CollisionShape3D so the brush has something to raycast against.
##   4. With the EZTreeDraw node selected, left-click / drag in the 3D
##      viewport to place trees. Hold Ctrl to erase (or set Tool Mode to
##      Erase). Set Tool Mode to Off to move the node or use gizmos again.
##
## Placed tree positions are saved with your scene; the tree meshes are
## regenerated from the template on load, so the painted forest is there at
## runtime with no extra work. If you change the template's look afterwards,
## press "Refresh Tree Meshes".

enum ToolMode { DRAW, ERASE, OFF }

## Draw places trees with left-click/drag (hold Ctrl to erase). Erase always
## erases. Off ignores viewport clicks so you can select/move things normally.
@export var tool_mode: ToolMode = ToolMode.DRAW
## When drawing, trees are placed with a random offset up to this radius
## around the cursor; when erasing, all trees within this radius are removed.
@export var brush_radius: float = 4.0
## Minimum distance between two trees; while dragging, a new tree is only
## placed once the cursor is clear of the existing ones.
@export var min_spacing: float = 10.0
## How many differently-shaped tree meshes to generate from the template
## (each gets a different rng_seed). More variants = less visible repetition,
## but all variants are regenerated on every scene load (positions are saved,
## meshes are not) and each variant used gets its own MultiMesh draw call, so
## very high counts cost load time and draw calls.
@export_range(1, 64) var variant_count: int = 32:
	set(v):
		variant_count = v
		_variant_meshes.clear()
## Random uniform scale range applied per tree.
@export var min_scale: float = 0.8
@export var max_scale: float = 1.2
## Give each tree a random rotation around its vertical axis.
@export var random_rotation := true
## Physics layers the ground collider is on.
@export_flags_3d_physics var collision_mask: int = 1

@export_tool_button("Refresh Tree Meshes") var _refresh_button: Callable = refresh_meshes
@export_tool_button("Clear Trees") var _clear_button: Callable = clear

## Painted data, saved with the scene. Kept out of the inspector.
@export_storage var _tree_transforms: Array[Transform3D] = []:
	set(v):
		_tree_transforms = v
		if is_node_ready():
			_rebuild_multimeshes()
@export_storage var _tree_variants := PackedInt32Array():
	set(v):
		_tree_variants = v
		if is_node_ready():
			_rebuild_multimeshes()

const _META_KEY := "eztree_draw"
const _DROP_HEIGHT := 200.0

var _variant_meshes: Array = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func _ready() -> void:
	if not _tree_transforms.is_empty():
		_rebuild_multimeshes()


func get_tree_count() -> int:
	return _tree_transforms.size()


## Places one tree near the given global position (jittered by brush_radius,
## re-dropped onto the ground, and rejected if within min_spacing of another
## tree). Called by the editor plugin while painting; also usable from code
## during physics processing.
func paint_at(global_pos: Vector3) -> void:
	if not _ensure_variant_meshes():
		return

	var target := global_pos
	if brush_radius > 0.0:
		# Uniform-ish jitter inside the brush disc
		var offset := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		if offset.length() > 1.0:
			offset = offset.normalized() * _rng.randf()
		offset *= brush_radius
		var jittered := global_pos + Vector3(offset.x, 0, offset.y)
		# Re-drop the jittered point onto the ground so it follows slopes
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			jittered + Vector3.UP * _DROP_HEIGHT,
			jittered + Vector3.DOWN * _DROP_HEIGHT,
			collision_mask)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			target = hit.position

	var local_pos := to_local(target)
	for t in _tree_transforms:
		if t.origin.distance_to(local_pos) < min_spacing:
			return

	var tree_basis := Basis.IDENTITY
	if random_rotation:
		tree_basis = Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
	tree_basis = tree_basis.scaled(Vector3.ONE * _rng.randf_range(min_scale, max_scale))

	# Reassign (rather than mutate in place) so the setters fire and any undo
	# snapshot of the previous arrays stays intact.
	var variants := _tree_variants.duplicate()
	variants.append(_rng.randi_range(0, variant_count - 1))
	_tree_variants = variants
	var transforms := _tree_transforms.duplicate()
	transforms.append(Transform3D(tree_basis, local_pos))
	_tree_transforms = transforms


## Removes all trees within brush_radius of the given global position.
func erase_at(global_pos: Vector3) -> void:
	var radius := maxf(brush_radius, 1.0)
	var local_pos := to_local(global_pos)
	var transforms: Array[Transform3D] = []
	var variants := PackedInt32Array()
	for i in range(_tree_transforms.size()):
		if _tree_transforms[i].origin.distance_to(local_pos) < radius:
			continue
		transforms.append(_tree_transforms[i])
		variants.append(_tree_variants[i] if i < _tree_variants.size() else 0)
	if transforms.size() == _tree_transforms.size():
		return
	_tree_variants = variants
	_tree_transforms = transforms


## Removes all painted trees (the template EZTree child is untouched).
func clear() -> void:
	_tree_variants = PackedInt32Array()
	_tree_transforms = []
	if is_node_ready():
		_rebuild_multimeshes()


## Regenerates the tree meshes from the template (use after re-tweaking the
## template EZTree child) and rebuilds the painted forest with them.
func refresh_meshes() -> void:
	_variant_meshes.clear()
	_rebuild_multimeshes()


func _find_template() -> EZTree:
	for child in get_children():
		if child is EZTree:
			return child
	return null


## Generates variant_count tree meshes from the template. Variant 0 keeps the
## template's own seed; the rest use seeds derived from it, so the same forest
## reappears on every load.
func _ensure_variant_meshes() -> bool:
	if _variant_meshes.size() == variant_count:
		return true
	var template := _find_template()
	if template == null:
		push_warning("EZTreeDraw: add an EZTree node as a child to use as the tree template.")
		return false
	_variant_meshes.clear()
	for v in range(variant_count):
		var dup: EZTree = template.duplicate()
		dup.rng_seed = template.rng_seed + v * 7919
		dup.generate()
		_variant_meshes.append(dup.get_tree_mesh())
		dup.free()
	return true


## Rebuilds the rendered forest: one MultiMesh per variant that is actually
## in use, each holding the transforms of every painted tree of that variant.
func _rebuild_multimeshes() -> void:
	for child in get_children(true):
		if child.has_meta(_META_KEY):
			remove_child(child)
			child.queue_free()

	if _tree_transforms.is_empty():
		return
	if not _ensure_variant_meshes():
		return

	var transforms_per_variant: Array = []
	for v in range(variant_count):
		transforms_per_variant.append([])
	var count := mini(_tree_transforms.size(), _tree_variants.size())
	for i in range(count):
		var variant := _tree_variants[i] % variant_count
		transforms_per_variant[variant].append(_tree_transforms[i])

	for v in range(variant_count):
		var transforms: Array = transforms_per_variant[v]
		if transforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _variant_meshes[v]
		mm.instance_count = transforms.size()
		for idx in range(transforms.size()):
			mm.set_instance_transform(idx, transforms[idx])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "EZTreeDrawVariant%d" % v
		mmi.set_meta(_META_KEY, true)
		mmi.multimesh = mm
		# Internal child: rebuilt from the stored transforms, never saved
		add_child(mmi, false, Node.INTERNAL_MODE_BACK)
