@tool
@icon("res://addons/ez-tree-godot-port/ez_tree_icon.svg")
class_name EZTree
extends Node3D
## Procedural tree generator. Based on EZ-Tree by Dan Greenheck
## (https://github.com/dgreenheck/ez-tree), MIT licensed.
##
## Drop an EZTree node into a 3D scene and a tree mesh is generated for you,
## regenerating live in the editor whenever you tweak a parameter.
## At runtime, call generate() after changing parameters in code.
##
## The tree is built in two passes:
##   1. Skeleton — branches grow section by section from a work queue, each
##      section randomly perturbed, twisted, and pulled toward a force
##      direction. Child branches and leaves are attached along the way.
##   2. Meshing — every branch becomes a tapered tube of vertex rings, every
##      leaf becomes one or two textured quads, and the results are committed
##      as two surfaces (bark and leaves) of a single ArrayMesh.
##
## The default parameter values produce an oak roughly 15 m tall.
## Lengths, radii and sizes are in meters.

const LeafWindShader = preload("res://addons/ez-tree-godot-port/leaf_wind.gdshader")

enum TreeType { DECIDUOUS, EVERGREEN }
enum BillboardMode { SINGLE, DOUBLE }

const BARK_COLOR := "res://addons/ez-tree-godot-port/textures/bark_color.jpg"
const BARK_NORMAL := "res://addons/ez-tree-godot-port/textures/bark_normal.jpg"
const BARK_ROUGHNESS := "res://addons/ez-tree-godot-port/textures/bark_roughness.jpg"
const LEAF_TEXTURE := "res://addons/ez-tree-godot-port/textures/leaf_oak.png"

## Same seed = same tree.
@export var rng_seed: int = 35729:
	set(v): rng_seed = v; _request_rebuild()

@export var tree_type: TreeType = TreeType.DECIDUOUS:
	set(v): tree_type = v; _request_rebuild()

@export_group("Bark", "bark_")
@export var bark_tint := Color8(255, 243, 209):
	set(v): bark_tint = v; _request_rebuild()
@export var bark_textured := true:
	set(v): bark_textured = v; _request_rebuild()
@export var bark_texture_scale := Vector2(4, 2.5):
	set(v): bark_texture_scale = v; _request_rebuild()

@export_group("Branch", "branch_")
## Number of branch recursion levels (0 = trunk only, max 3).
@export_range(0, 3) var branch_levels: int = 3:
	set(v): branch_levels = v; _request_rebuild()
## Angle of child branches relative to their parent, in degrees, per level
## (index = level; index 0 is unused).
@export var branch_angle := PackedFloat32Array([0, 54, 58, 32]):
	set(v): branch_angle = _fixed4f(v); _request_rebuild()
## Number of child branches per level (indices 0-2 are used).
@export var branch_children := PackedInt32Array([6, 4, 3, 0]):
	set(v): branch_children = _fixed4i(v); _request_rebuild()
## External force encouraging growth in a particular direction.
@export var branch_force_direction := Vector3(0, 1, 0):
	set(v): branch_force_direction = v; _request_rebuild()
@export var branch_force_strength: float = 0.005:
	set(v): branch_force_strength = v; _request_rebuild()
## Amount of random curling/twisting per level.
@export var branch_gnarliness := PackedFloat32Array([0, -0.05, -0.08, 0.05]):
	set(v): branch_gnarliness = _fixed4f(v); _request_rebuild()
## Branch length per level, in meters.
@export var branch_length := PackedFloat32Array([9.31, 2.77, 3.1, 1.79]):
	set(v): branch_length = _fixed4f(v); _request_rebuild()
## Branch radius per level. Index 0 is the trunk radius in meters; indices
## 1-3 are multipliers relative to the parent's radius at the attachment point.
@export var branch_radius := PackedFloat32Array([0.4, 0.9, 0.69, 1.19]):
	set(v): branch_radius = _fixed4f(v); _request_rebuild()
## Number of sections along each branch, per level.
@export var branch_sections := PackedInt32Array([8, 6, 3, 1]):
	set(v): branch_sections = _fixed4i(v); _request_rebuild()
## Number of radial segments around each branch, per level.
@export var branch_segments := PackedInt32Array([7, 5, 3, 3]):
	set(v): branch_segments = _fixed4i(v); _request_rebuild()
## Where along the parent (0-1) child branches start forming, per level
## (index 0 unused).
@export var branch_start := PackedFloat32Array([0, 0.49, 0.06, 0.12]):
	set(v): branch_start = _fixed4f(v); _request_rebuild()
## Radius taper along each branch, per level.
@export var branch_taper := PackedFloat32Array([0.73, 0.42, 0.69, 0.75]):
	set(v): branch_taper = _fixed4f(v); _request_rebuild()
## Twist around the growth axis, per level.
@export var branch_twist := PackedFloat32Array([-0.23, 0.42, 0, 0]):
	set(v): branch_twist = _fixed4f(v); _request_rebuild()

@export_group("Leaves", "leaf_")
## Single quad or two perpendicular quads per leaf.
@export var leaf_billboard: BillboardMode = BillboardMode.DOUBLE:
	set(v): leaf_billboard = v; _request_rebuild()
## Angle of leaves relative to the parent branch, in degrees.
@export var leaf_angle: float = 42.0:
	set(v): leaf_angle = v; _request_rebuild()
## Number of leaves per final-level branch.
@export var leaf_count: int = 18:
	set(v): leaf_count = v; _request_rebuild()
## Where leaves start to grow along the branch (0-1).
@export var leaf_start: float = 0.16:
	set(v): leaf_start = v; _request_rebuild()
@export var leaf_size: float = 0.6:
	set(v): leaf_size = v; _request_rebuild()
@export var leaf_size_variance: float = 0.7:
	set(v): leaf_size_variance = v; _request_rebuild()
@export var leaf_tint := Color8(213, 214, 205):
	set(v): leaf_tint = v; _request_rebuild()
## Alpha scissor threshold for the leaf texture.
@export_range(0.0, 1.0) var leaf_alpha_test: float = 0.5:
	set(v): leaf_alpha_test = v; _request_rebuild()
## Bend leaf normals outward to imply a rounded canopy shape.
@export var leaf_rounded_normals := true:
	set(v): leaf_rounded_normals = v; _request_rebuild()

@export_group("Wind", "wind_")
## Toggle leaf sway on/off.
@export var wind_enabled := true:
	set(v): wind_enabled = v; _request_rebuild()
## Maximum sway displacement per axis (world units). Y = 0 keeps the sway
## horizontal, like real foliage.
@export var wind_strength := Vector3(0.15, 0, 0.15):
	set(v): wind_strength = v; _request_rebuild()
## Speed of the sway oscillation.
@export var wind_frequency: float = 0.5:
	set(v): wind_frequency = v; _request_rebuild()
## Spatial size of the wind pattern. Larger values make bigger patches of the
## canopy move together; smaller values make leaves move more independently.
@export var wind_scale: float = 20.0:
	set(v): wind_scale = v; _request_rebuild()

var _rng := RandomNumberGenerator.new()
var _branch_queue: Array = []
var _skeleton_branches: Array = []
var _skeleton_leaves: Array = []
var _mesh_instance: MeshInstance3D
var _rebuild_queued := false


func _ready() -> void:
	generate()


## Regenerates the tree mesh from the current parameters.
func generate() -> void:
	_generate_skeleton()

	var branch_buf := _new_buffers()
	var leaf_buf := _new_buffers()
	for skeleton_branch in _skeleton_branches:
		_mesh_branch(branch_buf, skeleton_branch)
	for leaf in _skeleton_leaves:
		_mesh_leaf(leaf_buf, leaf)

	var mesh := ArrayMesh.new()
	if branch_buf.verts.size() > 0:
		_commit_surface(mesh, branch_buf, true)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _create_bark_material())
	if leaf_buf.verts.size() > 0:
		_commit_surface(mesh, leaf_buf, false)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _create_leaf_material())

	_get_mesh_instance().mesh = mesh


## Returns the generated ArrayMesh (bark surface + leaf surface, with
## materials). Used by EZTreeDraw, but also handy for saving the tree as a
## mesh resource.
func get_tree_mesh() -> ArrayMesh:
	return _get_mesh_instance().mesh


# --- Skeleton generation ---

func _generate_skeleton() -> void:
	_skeleton_branches = []
	_skeleton_leaves = []
	_rng.seed = rng_seed
	_branch_queue = [{
		origin = Vector3.ZERO,
		orientation = Vector3.ZERO,  # Euler angles, intrinsic XYZ order
		length = branch_length[0],
		radius = branch_radius[0],
		level = 0,
		section_count = branch_sections[0],
		segment_count = branch_segments[0],
	}]
	while _branch_queue.size() > 0:
		_grow_branch(_branch_queue.pop_front())


## Grows one branch section by section, then queues its children.
func _grow_branch(branch: Dictionary) -> void:
	var section_orientation: Vector3 = branch.orientation
	var section_origin: Vector3 = branch.origin
	var section_length: float = branch.length / branch.section_count

	var secs: Array = []

	for i in range(branch.section_count + 1):
		var section_radius: float = branch.radius

		# Final section of the final level tapers to (effectively) zero
		if i == branch.section_count and branch.level == branch_levels:
			section_radius = 0.001
		elif tree_type == TreeType.DECIDUOUS:
			section_radius *= 1.0 - branch_taper[branch.level] * (float(i) / branch.section_count)
		elif tree_type == TreeType.EVERGREEN:
			# Evergreens have no terminal branch, so they taper fully
			section_radius *= 1.0 - float(i) / branch.section_count

		secs.append({
			origin = section_origin,
			orientation = section_orientation,
			radius = section_radius,
		})

		# Step to the next section along the current growth direction
		section_origin += _quat_from_euler_xyz(section_orientation) \
			* Vector3(0, section_length, 0)

		# Random perturbation, scaled up for thin branches
		var gnarliness: float = \
			maxf(1.0, 1.0 / sqrt(section_radius)) * branch_gnarliness[branch.level]
		section_orientation.x += _rng.randf_range(-gnarliness, gnarliness)
		section_orientation.z += _rng.randf_range(-gnarliness, gnarliness)

		var q_section := _quat_from_euler_xyz(section_orientation)
		var q_twist := Quaternion(Vector3(0, 1, 0), branch_twist[branch.level])
		q_section = q_section * q_twist

		# Rotate the growth direction toward (or away from) the force direction.
		# Thin branches bend more than thick ones.
		var section_up: Vector3 = q_section * Vector3(0, 1, 0)
		var target := branch_force_direction.normalized()
		var axis := section_up.cross(target)
		var sin_full := axis.length()
		if sin_full > 1e-6:
			axis /= sin_full
			var full_angle := atan2(sin_full, section_up.dot(target))
			var step := branch_force_strength / section_radius
			var clamped := clampf(step, -full_angle, full_angle)
			q_section = Quaternion(axis, clamped) * q_section

		section_orientation = _euler_xyz_from_quat(q_section)

	_skeleton_branches.append({
		sections = secs,
		segment_count = branch.segment_count,
		base_radius = branch.radius,
	})

	# Deciduous trees have a terminal branch continuing from the parent's tip
	if tree_type == TreeType.DECIDUOUS:
		var last: Dictionary = secs[secs.size() - 1]
		if branch.level < branch_levels:
			_branch_queue.push_back({
				origin = last.origin,
				orientation = last.orientation,
				length = branch_length[branch.level + 1],
				radius = last.radius,
				level = branch.level + 1,
				# Same section/segment count as the parent so the junction stays sealed
				section_count = branch.section_count,
				segment_count = branch.segment_count,
			})
		else:
			_record_leaf(last.origin, last.orientation)

	if branch.level == branch_levels:
		_generate_leaves(secs)
	elif branch.level < branch_levels:
		_generate_child_branches(branch_children[branch.level], branch.level + 1, secs)


func _generate_child_branches(count: int, level: int, secs: Array) -> void:
	var radial_offset := _rng.randf()
	if count <= 0:
		return
	var start_min: float = branch_start[level]
	var height_step := (1.0 - start_min) / count
	var angle_slots := _shuffled_indices(count)

	for i in range(count):
		# Stratified sampling along the parent's length
		var child_start: float = start_min + (i + _rng.randf()) * height_step

		var section_index := int(floor(child_start * (secs.size() - 1)))
		var section_a: Dictionary = secs[section_index]
		var section_b: Dictionary = secs[section_index] if section_index == secs.size() - 1 \
			else secs[section_index + 1]

		var alpha: float = child_start * (secs.size() - 1) - section_index

		var child_origin: Vector3 = section_a.origin.lerp(section_b.origin, alpha)
		var child_radius: float = branch_radius[level] * \
			((1.0 - alpha) * section_a.radius + alpha * section_b.radius)

		var q_a := _quat_from_euler_xyz(section_a.orientation)
		var q_b := _quat_from_euler_xyz(section_b.orientation)
		var parent_orientation := _euler_xyz_from_quat(q_b.slerp(q_a, alpha))

		# Stratified radial angle with permuted slot assignment, so siblings
		# spread evenly around the parent without visible ordering.
		var radial_jitter := _rng.randf_range(-0.5, 0.5)
		var radial_angle := TAU * (radial_offset + (angle_slots[i] + radial_jitter) / count)
		var q1 := Quaternion(Vector3(1, 0, 0), deg_to_rad(branch_angle[level]))
		var q2 := Quaternion(Vector3(0, 1, 0), radial_angle)
		var q3 := _quat_from_euler_xyz(parent_orientation)
		var child_orientation := _euler_xyz_from_quat(q3 * (q2 * q1))

		# Evergreen branches get shorter toward the top, giving the conical shape
		var child_length: float = branch_length[level] * \
			(1.0 - child_start if tree_type == TreeType.EVERGREEN else 1.0)

		_branch_queue.push_back({
			origin = child_origin,
			orientation = child_orientation,
			length = child_length,
			radius = child_radius,
			level = level,
			section_count = branch_sections[level],
			segment_count = branch_segments[level],
		})


func _generate_leaves(secs: Array) -> void:
	var radial_offset := _rng.randf()
	var count := leaf_count
	if count <= 0:
		return
	var start_min := leaf_start
	var height_step := (1.0 - start_min) / count
	var angle_slots := _shuffled_indices(count)

	for i in range(count):
		# Stratified sampling along the branch, same scheme as child branches
		var lstart: float = start_min + (i + _rng.randf()) * height_step

		var section_index := int(floor(lstart * (secs.size() - 1)))
		var section_a: Dictionary = secs[section_index]
		var section_b: Dictionary = secs[section_index] if section_index == secs.size() - 1 \
			else secs[section_index + 1]

		var alpha: float = lstart * (secs.size() - 1) - section_index

		var leaf_origin: Vector3 = section_a.origin.lerp(section_b.origin, alpha)

		var q_a := _quat_from_euler_xyz(section_a.orientation)
		var q_b := _quat_from_euler_xyz(section_b.orientation)
		var parent_orientation := _euler_xyz_from_quat(q_b.slerp(q_a, alpha))

		var radial_jitter := _rng.randf_range(-0.5, 0.5)
		var radial_angle := TAU * (radial_offset + (angle_slots[i] + radial_jitter) / count)
		var q1 := Quaternion(Vector3(1, 0, 0), deg_to_rad(leaf_angle))
		var q2 := Quaternion(Vector3(0, 1, 0), radial_angle)
		var q3 := _quat_from_euler_xyz(parent_orientation)
		var leaf_orientation := _euler_xyz_from_quat(q3 * (q2 * q1))

		_record_leaf(leaf_origin, leaf_orientation)


func _record_leaf(origin: Vector3, orientation: Vector3) -> void:
	var size: float = leaf_size * \
		(1.0 + _rng.randf_range(-leaf_size_variance, leaf_size_variance))
	_skeleton_leaves.append({
		origin = origin,
		orientation = orientation,
		size = size,
	})


## Fisher-Yates shuffle of [0..count-1] using the tree's seeded RNG.
func _shuffled_indices(count: int) -> PackedInt32Array:
	var arr := PackedInt32Array()
	arr.resize(count)
	for k in range(count):
		arr[k] = k
	for k in range(count - 1, 0, -1):
		var r := _rng.randi_range(0, k)
		var tmp := arr[k]
		arr[k] = arr[r]
		arr[r] = tmp
	return arr


# --- Meshing ---

func _new_buffers() -> Dictionary:
	return {
		verts = PackedVector3Array(),
		normals = PackedVector3Array(),
		uvs = PackedVector2Array(),
		indices = PackedInt32Array(),
	}


## Builds a tapered, open-ended tube through the branch's sections: one ring
## of vertices per section, stitched into quads between consecutive rings.
func _mesh_branch(buf: Dictionary, skeleton_branch: Dictionary) -> void:
	var secs: Array = skeleton_branch.sections
	var seg_count: int = skeleton_branch.segment_count

	# Texture wraps around the circumference, scaled with the branch's base
	# radius so bark feature size stays consistent from trunk to twig.
	var wraps_x: int = maxi(1, roundi(skeleton_branch.base_radius * bark_texture_scale.x))

	var index_offset: int = buf.verts.size()

	for k in range(secs.size()):
		var section: Dictionary = secs[k]
		var q := _quat_from_euler_xyz(section.orientation)
		# V alternates 0/1 per ring so the bark texture tiles along the branch
		var vy := 1.0 if k % 2 == 0 else 0.0

		var first_vertex := Vector3.ZERO
		var first_normal := Vector3.ZERO
		for j in range(seg_count):
			var a := TAU * j / seg_count
			var dir := Vector3(cos(a), 0, sin(a))
			var vertex: Vector3 = q * (dir * section.radius) + section.origin
			var normal: Vector3 = (q * dir).normalized()
			buf.verts.push_back(vertex)
			buf.normals.push_back(normal)
			buf.uvs.push_back(Vector2(float(j) / seg_count * wraps_x, vy))
			if j == 0:
				first_vertex = vertex
				first_normal = normal

		# Duplicate the first vertex for UV continuity (u = wraps_x wraps to 0)
		buf.verts.push_back(first_vertex)
		buf.normals.push_back(first_normal)
		buf.uvs.push_back(Vector2(wraps_x, vy))

	# Two clockwise-wound triangles per quad between consecutive rings
	var n := seg_count + 1
	for i in range(secs.size() - 1):
		for j in range(seg_count):
			var v1 := index_offset + i * n + j
			var v2 := v1 + 1
			var v3 := v1 + n
			var v4 := v2 + n
			buf.indices.push_back(v2)
			buf.indices.push_back(v3)
			buf.indices.push_back(v1)
			buf.indices.push_back(v4)
			buf.indices.push_back(v3)
			buf.indices.push_back(v2)


func _mesh_leaf(buf: Dictionary, leaf: Dictionary) -> void:
	_emit_leaf_quad(buf, leaf, 0.0)
	if leaf_billboard == BillboardMode.DOUBLE:
		_emit_leaf_quad(buf, leaf, PI / 2.0)


func _emit_leaf_quad(buf: Dictionary, leaf: Dictionary, rotation_y: float) -> void:
	var i: int = buf.verts.size()
	var origin: Vector3 = leaf.origin
	var orientation: Vector3 = leaf.orientation
	var w: float = leaf.size
	var l: float = leaf.size

	var q_rot := Quaternion(Vector3(0, 1, 0), rotation_y)
	var q_orient := _quat_from_euler_xyz(orientation)

	# Quad anchored at its base (the attachment point) growing along local +Y
	var local := [
		Vector3(-w / 2.0, l, 0),
		Vector3(-w / 2.0, 0, 0),
		Vector3(w / 2.0, 0, 0),
		Vector3(w / 2.0, l, 0),
	]
	var verts: Array = []
	for lv in local:
		verts.append(q_orient * (q_rot * lv) + origin)

	var n: Vector3 = q_orient * Vector3(0, 0, 1)
	for k in range(4):
		buf.verts.push_back(verts[k])
		if leaf_rounded_normals:
			# Blend the leaf direction with the direction to the vertex for a
			# rounded canopy look.
			buf.normals.push_back((n + verts[k] - origin).normalized())
		else:
			buf.normals.push_back(n)

	# UV.y = 1 at the attachment point; the wind shader relies on this to
	# keep the leaf base anchored while the tip sways.
	buf.uvs.push_back(Vector2(0, 0))
	buf.uvs.push_back(Vector2(0, 1))
	buf.uvs.push_back(Vector2(1, 1))
	buf.uvs.push_back(Vector2(1, 0))

	buf.indices.push_back(i + 2)
	buf.indices.push_back(i + 1)
	buf.indices.push_back(i)
	buf.indices.push_back(i + 3)
	buf.indices.push_back(i + 2)
	buf.indices.push_back(i)


func _commit_surface(mesh: ArrayMesh, buf: Dictionary, with_tangents: bool) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buf.verts
	arrays[Mesh.ARRAY_NORMAL] = buf.normals
	arrays[Mesh.ARRAY_TEX_UV] = buf.uvs
	arrays[Mesh.ARRAY_INDEX] = buf.indices

	if with_tangents:
		# Round-trip through SurfaceTool to generate tangents (needed for the
		# bark normal map).
		var tmp := ArrayMesh.new()
		tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var st := SurfaceTool.new()
		st.create_from(tmp, 0)
		st.generate_tangents()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	else:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# --- Materials ---

func _create_bark_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = bark_tint
	mat.metallic = 0.0
	mat.roughness = 1.0
	if bark_textured:
		var color_tex := _load_texture(BARK_COLOR)
		if color_tex:
			mat.albedo_texture = color_tex
		var normal_tex := _load_texture(BARK_NORMAL)
		if normal_tex:
			mat.normal_enabled = true
			mat.normal_texture = normal_tex
		var rough_tex := _load_texture(BARK_ROUGHNESS)
		if rough_tex:
			mat.roughness_texture = rough_tex
		# texture_scale.x is baked into the UVs (wraps_x); only Y scales here
		mat.uv1_scale = Vector3(1.0, 1.0 / maxf(0.0001, bark_texture_scale.y), 1.0)
	return mat


func _create_leaf_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = LeafWindShader
	var tex := _load_texture(LEAF_TEXTURE)
	if tex:
		mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("tint", leaf_tint)
	mat.set_shader_parameter("alpha_scissor", leaf_alpha_test)
	mat.set_shader_parameter("wind_strength", wind_strength if wind_enabled else Vector3.ZERO)
	mat.set_shader_parameter("wind_frequency", wind_frequency)
	mat.set_shader_parameter("wind_scale", wind_scale)
	return mat


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("EZTree: texture not found: " + path)
	return null


# --- Euler math ---
# The generator stores orientations as Euler angles and perturbs individual
# components while growing (e.g. section_orientation.x above), so the
# rotation order is part of the algorithm. It uses intrinsic XYZ order, which
# differs from Godot's built-in YXZ convention — hence these helpers.

static func _quat_from_euler_xyz(e: Vector3) -> Quaternion:
	var c1 := cos(e.x / 2.0)
	var c2 := cos(e.y / 2.0)
	var c3 := cos(e.z / 2.0)
	var s1 := sin(e.x / 2.0)
	var s2 := sin(e.y / 2.0)
	var s3 := sin(e.z / 2.0)
	return Quaternion(
		s1 * c2 * c3 + c1 * s2 * s3,
		c1 * s2 * c3 - s1 * c2 * s3,
		c1 * c2 * s3 + s1 * s2 * c3,
		c1 * c2 * c3 - s1 * s2 * s3)


static func _euler_xyz_from_quat(q: Quaternion) -> Vector3:
	# Decompose via the rotation matrix; only the entries needed for the
	# XYZ-order extraction are computed.
	var xx := q.x * q.x
	var yy := q.y * q.y
	var zz := q.z * q.z
	var xy := q.x * q.y
	var xz := q.x * q.z
	var yz := q.y * q.z
	var wx := q.w * q.x
	var wy := q.w * q.y
	var wz := q.w * q.z

	var m11 := 1.0 - 2.0 * (yy + zz)
	var m12 := 2.0 * (xy - wz)
	var m13 := 2.0 * (xz + wy)
	var m22 := 1.0 - 2.0 * (xx + zz)
	var m23 := 2.0 * (yz - wx)
	var m32 := 2.0 * (yz + wx)
	var m33 := 1.0 - 2.0 * (xx + yy)

	var ey := asin(clampf(m13, -1.0, 1.0))
	var ex: float
	var ez: float
	if absf(m13) < 0.9999999:
		ex = atan2(-m23, m33)
		ez = atan2(-m12, m11)
	else:
		# Gimbal lock: pitch is ±90°, roll folds into the other two angles
		ex = atan2(m32, m22)
		ez = 0.0
	return Vector3(ex, ey, ez)


# --- Internals ---

static func _fixed4f(v: PackedFloat32Array) -> PackedFloat32Array:
	v.resize(4)
	return v


static func _fixed4i(v: PackedInt32Array) -> PackedInt32Array:
	v.resize(4)
	return v


## Editor changes arrive one property at a time; coalesce them into a single
## deferred rebuild.
func _request_rebuild() -> void:
	if not is_node_ready() or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_deferred_rebuild")


func _deferred_rebuild() -> void:
	_rebuild_queued = false
	generate()


func _get_mesh_instance() -> MeshInstance3D:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		return _mesh_instance
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "TreeMesh"
	# Internal child: regenerated on load, never saved into the scene file
	add_child(_mesh_instance, false, Node.INTERNAL_MODE_BACK)
	return _mesh_instance
