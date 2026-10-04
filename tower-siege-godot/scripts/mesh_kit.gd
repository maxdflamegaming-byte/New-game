class_name MeshKit
extends RefCounted
## Builds one mesh out of many simple shapes (boxes, hex prisms, cones, spheres), so a whole
## building or soldier is drawn in one go. Each shape gets a color baked into its vertices,
## or a tag meaning "the army's color" (see shaders/paint.gdshader).

const TEAM := 0.5
const DARK := 0.25
const LIGHT := 0.75

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uv2s := PackedVector2Array()
var indices := PackedInt32Array()


## color: a Color, or TEAM / DARK / LIGHT. leg: (1 or 2, hip height) for a soldier's legs.
func add(m: PrimitiveMesh, xf: Transform3D, color, leg := Vector2.ZERO) -> MeshKit:
	var arr := m.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var c: Color
	if color is Color:
		c = (color as Color).srgb_to_linear()
		c.a = 1.0
	else:
		c = Color(0, 0, 0, color)
	var off := verts.size()
	for i in v.size():
		verts.append(xf * v[i])
		normals.append((xf.basis * n[i]).normalized())
		colors.append(c)
		uv2s.append(leg)
	for i in idx:
		indices.append(i + off)
	return self


func box(w: float, h: float, d: float, pos: Vector3, color, ry := 0.0, leg := Vector2.ZERO) -> MeshKit:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return add(b, Transform3D(Basis(Vector3.UP, ry), pos), color, leg)


func cyl(rt: float, rb: float, h: float, segs: int, pos: Vector3, color, basis := Basis()) -> MeshKit:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = segs
	c.rings = 0
	return add(c, Transform3D(basis, pos), color)


## A hexagonal prism with a flat face toward the camera
func hex(rt: float, rb: float, h: float, pos: Vector3, color) -> MeshKit:
	return cyl(rt, rb, h, 6, pos, color, Basis(Vector3.UP, PI / 6))


func cone(r: float, h: float, segs: int, pos: Vector3, color, basis := Basis()) -> MeshKit:
	return cyl(0.001, r, h, segs, pos, color, basis)


func sphere(r: float, pos: Vector3, color, scale := Vector3.ONE, hemi := false, segs := 10, rings := 6) -> MeshKit:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2
	s.is_hemisphere = hemi
	s.radial_segments = segs
	s.rings = rings
	return add(s, Transform3D(Basis.from_scale(scale), pos), color)


func mesh() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	if not verts.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
