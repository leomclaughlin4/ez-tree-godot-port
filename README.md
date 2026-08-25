# ez-tree-godot-port

A procedural tree generator for Godot 4, based on
[EZ-Tree](https://github.com/dgreenheck/ez-tree) by Dan Greenheck (MIT license).

Two nodes:

- **EZTree** — generates a single tree mesh from adjustable parameters,
  rebuilding live in the editor as you tweak them.
- **EZTreeDraw** — paints forests of EZTree trees onto your ground geometry
  with a brush, directly in the 3D viewport.

## Generating a tree (EZTree)

1. Add an **EZTree** node to any 3D scene (it shows up in the Create Node
   dialog). A tree generates immediately.
2. Tweak any parameter in the inspector — seed, branch levels, angles,
   lengths, gnarliness, leaves — and the mesh rebuilds live in the editor.

The default parameters produce an oak roughly 15 m tall (lengths, radii and
sizes are in meters). Changing **rng_seed**
gives a different tree of the same character; the same seed always produces
the same tree. Both deciduous and evergreen shapes are supported
(**tree_type**).

From code:

```gdscript
var tree := EZTree.new()
add_child(tree)
tree.rng_seed = 12345
tree.generate()  # rebuild immediately (editor changes rebuild automatically)
```

The generated mesh lives in an internal `MeshInstance3D` child that is
rebuilt on load and never saved into your scene file. `get_tree_mesh()`
returns the `ArrayMesh` (bark + leaf surfaces with materials) if you want to
save it as a resource or instance it yourself.

A demo scene is included at
`res://addons/ez-tree-godot-port/demo/ez_tree_demo.tscn`.

## Wind sway

The leaves sway via a vertex shader (three layered sine waves with a
simplex-noise phase, anchored at each leaf's attachment point). The **Wind**
group on the EZTree node controls it:

- `wind_enabled` — toggle sway on/off
- `wind_strength` — max displacement per axis; keep Y at 0 for horizontal sway
- `wind_frequency` — oscillation speed
- `wind_scale` — size of the wind pattern; larger = bigger patches of canopy
  moving together

The shader is driven by `TIME`, so it animates in the editor and in game with
no script running.

## Painting forests (EZTreeDraw)

Tree placement raycasts against your ground's **StaticBody3D collision** —
the ground `MeshInstance3D` needs a StaticBody3D + CollisionShape3D.

1. Add an **EZTreeDraw** node to your scene.
2. Add an **EZTree** node as a *child* of it — the template. Tweak it, then
   hide it if you don't want the preview tree.
3. With the EZTreeDraw node selected, **left-click / drag** in the 3D
   viewport to place trees on your ground collision. A **brush ring** is
   projected onto the ground under the cursor — green while drawing, red
   while erasing. **Hold Ctrl to erase** trees under the brush (or set
   **Tool Mode** to Erase). Editor **undo/redo works** per stroke.
4. Set **Tool Mode** to Off when you want viewport clicks to behave normally
   again (selecting other nodes, gizmos, etc.).

Brush behavior: each placement is jittered up to `brush_radius` around the
cursor and re-dropped onto the ground, and trees keep `min_spacing` apart —
so dragging paints a natural-looking line of forest rather than a blob. Each
tree gets a random rotation, a random scale in `[min_scale, max_scale]`, and
one of `variant_count` differently-seeded shapes generated from your template
(up to 64 variants; more variants = less visible repetition).

Painted positions are saved with the scene; the heavy tree meshes are not —
they're regenerated from the template on load, in the editor and at runtime,
and rendered with one `MultiMesh` per variant. If you re-tweak the template
afterwards, press **Refresh Tree Meshes** to apply the new look to the
painted forest, or **Clear Trees** to start over.

If painting does nothing: reload the project (Project > Reload Current
Project) so the editor picks up the plugin, make sure the EZTreeDraw node has
an EZTree child (a warning is printed when you select it without one), and
check that the ground's StaticBody3D is on a layer included in
**Collision Mask**.

## Files

- `ez_tree.gd` — the EZTree node: skeleton growth, meshing, and materials
- `ez_tree_draw.gd` — the EZTreeDraw painting node
- `plugin.gd` — editor plugin providing the viewport painting input for
  EZTreeDraw
- `leaf_wind.gdshader` — leaf material with the wind sway
- `textures/` — one bark set (color/normal/roughness) and one oak leaf
  texture

## Credits / licenses

- Based on the EZ-Tree library: MIT, © Dan Greenheck (see LICENSE)
- Bark textures: [ambientCG](https://ambientcg.com) (CC0)
- Simplex noise in the leaf shader: [ashima/webgl-noise](https://github.com/ashima/webgl-noise) (MIT)
