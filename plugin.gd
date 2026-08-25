@tool
extends EditorPlugin
## Editor integration for ez-tree-godot-port.
##
## The EZTree and EZTreeDraw nodes are registered globally via their
## class_name. This plugin adds the viewport painting for EZTreeDraw:
## while an EZTreeDraw node is selected, left-click/drag in the 3D viewport
## places trees (Ctrl erases). A projected ring decal shows the brush —
## green when drawing, red when erasing.

var _current: EZTreeDraw = null
var _stroke_active := false
var _erase_mode := false
var _brush_decal: Decal = null

const _DRAW_COLOR := Color(0.35, 1.0, 0.45)
const _ERASE_COLOR := Color(1.0, 0.35, 0.3)


func _exit_tree() -> void:
	_end_stroke()
	_free_decal()


func _handles(object) -> bool:
	return object is EZTreeDraw


func _edit(object) -> void:
	_end_stroke()
	_free_decal()
	_current = object as EZTreeDraw
	if _current != null and _current._find_template() == null:
		push_warning("EZTreeDraw: add an EZTree node as a child of '%s' to use as the tree template before painting." % _current.name)


func _make_visible(visible: bool) -> void:
	if not visible:
		_end_stroke()
		_free_decal()
		_current = null


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if _current == null or not is_instance_valid(_current) or not _current.is_inside_tree():
		return AFTER_GUI_INPUT_PASS
	if _current.tool_mode == EZTreeDraw.ToolMode.OFF:
		_hide_decal()
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_end_stroke()  # safety if a release event was missed
			_stroke_active = true
			_erase_mode = event.ctrl_pressed \
				or _current.tool_mode == EZTreeDraw.ToolMode.ERASE
			var undo := get_undo_redo()
			undo.create_action(String(_current.name)
				+ (" Erase Trees" if _erase_mode else " Paint Trees"))
			undo.add_undo_property(_current, &"_tree_transforms", _current._tree_transforms)
			undo.add_undo_property(_current, &"_tree_variants", _current._tree_variants)
			_apply_brush(viewport_camera, event.position)
		else:
			_end_stroke()
		return AFTER_GUI_INPUT_STOP

	if event is InputEventMouseMotion:
		if _stroke_active:
			_apply_brush(viewport_camera, event.position)
			return AFTER_GUI_INPUT_STOP
		# Hovering: just move the brush ring, let the editor handle the event
		var hover_erase := _current.tool_mode == EZTreeDraw.ToolMode.ERASE
		_update_decal(_raycast(viewport_camera, event.position), hover_erase)
		return AFTER_GUI_INPUT_PASS

	return AFTER_GUI_INPUT_PASS


func _raycast(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var space := _current.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		from, from + dir * 100000.0, _current.collision_mask)
	return space.intersect_ray(query)


func _apply_brush(camera: Camera3D, mouse_pos: Vector2) -> void:
	var hit := _raycast(camera, mouse_pos)
	_update_decal(hit, _erase_mode)
	if hit.is_empty():
		return
	if _erase_mode:
		_current.erase_at(hit.position)
	else:
		_current.paint_at(hit.position)


func _end_stroke() -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	if _current != null and is_instance_valid(_current):
		var undo := get_undo_redo()
		undo.add_do_property(_current, &"_tree_transforms", _current._tree_transforms)
		undo.add_do_property(_current, &"_tree_variants", _current._tree_variants)
		undo.commit_action()


# --- Brush ring decal ---

func _update_decal(hit: Dictionary, erase: bool) -> void:
	if _current == null or not is_instance_valid(_current) or not _current.is_inside_tree():
		return
	_ensure_decal()
	if hit.is_empty():
		_brush_decal.visible = false
		return
	var radius: float = maxf(_current.brush_radius, 1.0)
	_brush_decal.size = Vector3(radius * 2.0, 20.0, radius * 2.0)
	_brush_decal.modulate = _ERASE_COLOR if erase else _DRAW_COLOR
	_brush_decal.visible = true
	_brush_decal.global_position = hit.position


func _hide_decal() -> void:
	if _brush_decal != null and is_instance_valid(_brush_decal):
		_brush_decal.visible = false


func _ensure_decal() -> void:
	if _brush_decal != null and is_instance_valid(_brush_decal) \
			and _brush_decal.get_parent() == _current:
		return
	_free_decal()
	_brush_decal = Decal.new()
	_brush_decal.name = "EZTreeBrushRing"
	_brush_decal.texture_albedo = _make_ring_texture()
	_brush_decal.visible = false
	# Internal, unowned child of the painted node: renders in the edited
	# scene's world but is never saved with it.
	_current.add_child(_brush_decal, false, Node.INTERNAL_MODE_BACK)


func _free_decal() -> void:
	if _brush_decal != null and is_instance_valid(_brush_decal):
		_brush_decal.get_parent().remove_child(_brush_decal)
		_brush_decal.queue_free()
	_brush_decal = null


## A white ring with a faint filled center, drawn as a radial gradient.
## The decal's modulate supplies the draw/erase color.
func _make_ring_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	grad.offsets = PackedFloat32Array([0.0, 0.82, 0.96])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.08),  # faint fill inside the ring
		Color(1, 1, 1, 0.85),  # the ring itself
		Color(0, 0, 0, 0.0),   # outside
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	return tex
