package af// short for Application Framework

import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:runtime"
import "core:strings"
import "core:time"
import gl "vendor:OpenGL"
import "vendor:glfw"

Mat4 :: linalg.Matrix4f32
MAT4_IDENTITY :: linalg.MATRIX4F32_IDENTITY

Color :: linalg.Vector4f32
Vec4 :: linalg.Vector4f32
Vec3 :: linalg.Vector3f32
Vec2 :: linalg.Vector2f32
Quat :: linalg.Quaternionf32

GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 3

KEYBOARD_CHARS :: "\t\b\n `1234567890-=qwertyuiop[]asdfghjkl;'\\zxcvbnm,./"

// Window state

window_title: string
target_fps: int
window: glfw.WindowHandle
last_frame_time: f64
delta_time: f32
layout_rect: Rect

window_rect: Rect // NOTE: x0, y0 are always zero. 
framebuffer_rect: Rect

// Render state

white_pixel_texture: ^Texture
im: ^MeshBuffer // use this mesh buffer to render things in an immediate mode style
internal_shader: ^Shader

transform, view, projection: Mat4
draw_color: Color

current_shader: ^Shader
current_framebuffer: ^Framebuffer
current_texture: ^Texture

// Input state

keyboard_state_prev := [KeyCode_Max]bool{}
keyboard_state_curr := [KeyCode_Max]bool{}

inputted_runes := [KeyCode_Max]rune{}
inputted_runes_count: int
is_any_down, was_any_down: bool

keys_just_pressed := [KeyCode_Max]KeyCode{} // should also capture repeats
keys_just_pressed_count: int

incoming_mouse_wheel_notches: f32 = 0
mouse_wheel_notches: f32 = 0
prev_mouse_button_states := [MBCode]bool{}
mouse_button_states := [MBCode]bool{}
mouse_was_any_down, mouse_any_down: bool

internal_prev_mouse_position: Vec2
internal_mouse_position: Vec2
mouse_delta: Vec2

stencil_mode: StencilMode


// (\w+) (\*?)([\w_]+)

get_time :: proc() -> f64 {
	return glfw.GetTime()
}

set_time :: proc(t: f64) {
	glfw.SetTime(t)
}

// Short for layout_rect.width
vw :: proc() -> f32 {
	return layout_rect.width
}

// Short for layout_rect.height
vh :: proc() -> f32 {
	return layout_rect.height
}

set_target_fps :: proc(fps: int) {
	target_fps = fps
}

window_should_close :: proc() -> bool {
	return glfw.WindowShouldClose(window) == true
}


internal_glfw_character_callback :: proc "c" (window: glfw.WindowHandle, r: rune) {
	if (inputted_runes_count >= len(inputted_runes)) {
		context = runtime.default_context()
		debug_log("WARNING - text buffer is full")
		return
	}

	inputted_runes[inputted_runes_count] = r
	inputted_runes_count += 1
}

internal_glfw_key_callback :: proc "c" (
	window: glfw.WindowHandle,
	key, scancode, action, mods: c.int,
) {
	if (action == glfw.RELEASE) {
		return
	}

	if (keys_just_pressed_count >= len(keys_just_pressed)) {
		context = runtime.default_context()
		debug_log("WARNING - key input buffer is full")
		return
	}

	keys_just_pressed[keys_just_pressed_count] = KeyCode(key)
	keys_just_pressed_count += 1
}

internal_glfw_framebuffer_size_callback :: proc "c" (
	window: glfw.WindowHandle,
	width, height: c.int,
) {
	window_rect.width = f32(width)
	window_rect.height = f32(height)

	context = runtime.default_context()
	internal_on_framebuffer_resize(width, height)
}

@(private)
internal_on_framebuffer_resize :: proc(width, height: c.int) {
	framebuffer_rect.width = f32(width)
	framebuffer_rect.height = f32(height)

	set_layout_rect(layout_rect, false)
	gl.Viewport(0, 0, width, height)
}


internal_set_texture_directly :: proc(texture: ^Texture) {
	texture := texture
	if (texture == nil) {
		texture = white_pixel_texture
	}

	internal_set_texture_unit(gl.TEXTURE0)
	internal_use_texture(texture)
	current_texture = texture
}

set_texture :: proc(texture: ^Texture) {
	if (texture == current_texture) {
		return
	}

	flush()
	internal_set_texture_directly(texture)
}

clear_screen :: proc(col: Color) {
	flush()

	gl.ClearColor(col.r, col.g, col.b, col.a)

	// the stencil buffer but must be cleared manually
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}

flush :: proc() {
	flush_mesh_buffer(im)
}

set_layout_rect :: proc(rect: Rect, clip := false) {
	flush()

	layout_rect = rect

	if (clip) {
		gl.Scissor(
			c.int(layout_rect.x0),
			c.int(layout_rect.y0),
			c.int(layout_rect.width),
			c.int(layout_rect.height),
		)

		gl.Enable(gl.SCISSOR_TEST)
	} else {
		gl.Disable(gl.SCISSOR_TEST)
	}

	set_camera_2D(0, 0, 1, 1)
}

set_window_title :: proc(title: string) {
	window_title = title
	title_cstr := strings.clone_to_cstring(title)
	glfw.SetWindowTitle(window, title_cstr)
	delete(title_cstr)
}

iconify_window :: proc() {
	glfw.IconifyWindow(window)
}
restore_window :: proc() {
	glfw.RestoreWindow(window)
}
maximize_window :: proc() {
	glfw.MaximizeWindow(window)
}
show_window :: proc() {
	glfw.ShowWindow(window)
}
hide_window :: proc() {
	glfw.HideWindow(window)
}
focus_window :: proc() {
	glfw.FocusWindow(window)
}

initialize :: proc(width: int, height: int) -> bool {
	debug_log("Initializing window ... ")
	{
		if (!bool(glfw.Init())) {
			debug_log("glfw failed to initialize")
			return false
		}

		glfw.WindowHint(glfw.VISIBLE, 0)

		window = glfw.CreateWindow(c.int(width), c.int(height), "", nil, nil)
		if (window == nil) {
			debug_log("glfw failed to create a window")
			glfw.Terminate()
			return false
		}

		/* Make the window's context current */
		glfw.MakeContextCurrent(window)

		glfw.SetScrollCallback(window, internal_glfw_scroll_callback)
		glfw.SetKeyCallback(window, internal_glfw_key_callback)
		glfw.SetCharCallback(window, internal_glfw_character_callback)
		glfw.SetFramebufferSizeCallback(window, internal_glfw_framebuffer_size_callback)

		debug_log("GLFW initialized\n")
	}


	debug_log("Initializing Rendering ... ")
	{
		gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)

		im = new_mesh_buffer(2000, 6000)
		internal_shader = new_shader_default()
		set_shader(internal_shader)

		gl.Enable(gl.BLEND)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

		gl.Enable(gl.STENCIL_TEST)
		gl.StencilFunc(gl.EQUAL, 0, 0xFF)

		gl.Enable(gl.DEPTH_TEST)

		set_backface_culling(false)

		// init blank texture
		{
			img: Image
			img.width = 1
			img.height = 1
			img.num_channels = 4

			data := make([]byte, 4)
			defer delete(data)
			data[0] = 0xFF
			data[1] = 0xFF
			data[2] = 0xFF
			data[3] = 0xFF
			img.data = raw_data(data)

			config := DEFAULT_TEXTURE_CONFIG
			config.filtering = gl.NEAREST
			white_pixel_texture = new_texture_from_image(&img, config)
		}

		debug_log(
			"OpenGL initialized. OpenGL info: %s, Version: %s",
			gl.GetString(gl.VENDOR),
			gl.GetString(gl.VERSION),
		)
	}

	internal_initialize_text()
	debug_log("Text initialized [SDL2::TTF]")

	return true
}

begin_frame :: proc() {
	internal_update_key_inputs_before_poll()
	glfw.PollEvents()
	internal_update_mouse_input()
	internal_update_key_input()

	w, h := glfw.GetWindowSize(window)
	window_rect.width = f32(w)
	window_rect.height = f32(h)

	set_transform(linalg.MATRIX4F32_IDENTITY)
	internal_set_texture_directly(nil)
	internal_set_framebuffer_directly(nil)

	set_layout_rect(window_rect, false)

	reset_mesh_stats()
}

end_frame :: proc() {
	flush()
	internal_set_framebuffer_directly(nil)
	set_stencil_mode(.Off)
	glfw.SwapBuffers(window)

	frame_end := get_time()
	delta_time = f32(frame_end - last_frame_time)

	if (target_fps == 0) {
		last_frame_time = frame_end
		return
	}

	// This is a power saving mechanism that will sleep the thread if we
	// have the time available to do so. It should reduce the overall CPU consumption.

	frame_duration := 1 / f64(target_fps)
	time_to_next_frame := frame_duration - f64(delta_time)
	if (time_to_next_frame > 0) {
		nanoseconds := i64(time_to_next_frame * 1000000000)
		time.sleep(time.Duration(nanoseconds))

		frame_end = get_time()
		delta_time = f32(frame_end - last_frame_time)
	}

	last_frame_time = frame_end
}

un_initialize :: proc() {
	debug_log("UnInitializing...")

	// free rendering resources
	free_shader(internal_shader)
	free_mesh_buffer(im)
	free_texture(white_pixel_texture)

	glfw.Terminate()

	internal_un_initialize_text()

	debug_log("Done")
}

set_camera_2D :: proc(x, y, scale_x, scale_y: f32) {
	x := layout_rect.x0 + x
	y := layout_rect.y0 + y

	width := scale_x * framebuffer_rect.width
	height := scale_y * framebuffer_rect.height

	translation := Vec3{x - width / 2, y - height / 2, 0}
	view := linalg.matrix4_translate(translation)

	scale := Vec3{2 / width, 2 / height, 1}
	projection := linalg.matrix4_scale(scale)

	set_view(view)
	set_projection(projection)

	gl.DepthFunc(gl.LEQUAL)
}

set_camera_3D :: proc(pos: Vec3, rot: Quat, projection: Mat4) {
	rot_inverse := linalg.quaternion_inverse(rot)
	// rot_inverse := rot
	tr := linalg.matrix4_translate(-pos)
	rot := linalg.matrix4_from_quaternion(rot_inverse)
	set_view(linalg.mul(rot, tr))

	set_projection(projection)

	gl.DepthFunc(gl.LESS)
}

get_look_at :: proc(position: Vec3, target: Vec3, up: Vec3) -> Mat4 {
	return linalg.matrix4_look_at_f32(position, target, up)
}

get_orientation :: proc(position: Vec3, rotation: Quat) -> Mat4 {
	view := linalg.mul(
		linalg.matrix4_from_quaternion(rotation),
		linalg.matrix4_translate(position),
	)
	return view
}

internal_get_layout_rect_center_offset :: proc() -> Mat4 {
	// A translation in clipspace from the center of the framebuffer to the center of the current layout rect
	center_x := (layout_rect.x0 + vw() * 0.5) - framebuffer_rect.width * 0.5
	center_y := (layout_rect.y0 + vh() * 0.5) - framebuffer_rect.height * 0.5
	center_x_clipspace := 2 * center_x / framebuffer_rect.width
	center_y_clipspace := 2 * center_y / framebuffer_rect.height
	screen_center := linalg.matrix4_translate(Vec3{center_x_clipspace, center_y_clipspace, 0})

	return screen_center
}

get_perspective :: proc(fovy, depth_near, depth_far: f32) -> Mat4 {
	projection := linalg.matrix4_perspective(fovy, vw() / vh(), depth_near, depth_far, false)
	center_offset := internal_get_layout_rect_center_offset()
	return linalg.mul(center_offset, projection)
}


get_orthographic :: proc(size, depth_near, depth_far: f32) -> Mat4 {
	ySize := size
	xSize := size * vw() / vh()

	projection := linalg.matrix_ortho3d_f32(
		-xSize,
		xSize,
		-ySize,
		ySize,
		depth_near,
		depth_far,
		false,
	)
	center_offset := internal_get_layout_rect_center_offset()
	return linalg.mul(center_offset, projection)
}


set_projection :: proc(mat: Mat4) {
	flush()

	projection = mat
	set_shader_mat4(current_shader.projection_loc, &projection)
}

set_transform :: proc(mat: Mat4) {
	flush()

	transform = mat
	set_shader_mat4(current_shader.transform_loc, &transform)
}

set_view :: proc(mat: Mat4) {
	flush()

	view = mat
	set_shader_mat4(current_shader.view_loc, &view)
}

set_color :: proc(color: Color) {
	flush()

	draw_color = color
	set_shader_vec4(current_shader.color_loc, draw_color)
}

set_backface_culling :: proc(state: bool) {
	flush()

	if (state) {
		gl.Enable(gl.CULL_FACE)
	} else {
		gl.Disable(gl.CULL_FACE)
	}
}

set_shader :: proc(shader: ^Shader) {
	flush()

	shader := shader
	if (shader == nil) {
		shader = internal_shader
	}

	current_shader = shader
	internal_shader_use(current_shader)
	set_shader_mat4(current_shader.transform_loc, &transform)
	set_shader_mat4(current_shader.view_loc, &view)
	set_shader_mat4(current_shader.projection_loc, &projection)
}

clear_stencil :: proc() {
	flush()

	gl.ClearStencil(0)
	gl.Clear(gl.STENCIL_BUFFER_BIT)
}

clear_depth_buffer :: proc() {
	flush()

	gl.Clear(gl.DEPTH_BUFFER_BIT)
}

StencilMode :: enum {
	WriteOnes, // writes 0xFF where fragments appear
	WriteZeroes, // writes 0 where fragments appear
	DrawOverOnes, // allows fragments only where the buffer is 0xFF
	DrawOverZeroes, // allows fragments only where the buffer is 0
	Off, // disables the stencil
}

set_stencil_mode :: proc(mode: StencilMode) {
	flush()

	// TODO: use stencil_mode
	stencil_mode = mode

	if mode == .Off {
		gl.Disable(gl.STENCIL_TEST)
		return
	}

	gl.Enable(gl.STENCIL_TEST)

	// sfail, zfail, zpass. TODO: I would like more control over this later
	gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE)

	switch mode {
	case .WriteOnes:
		gl.StencilMask(0xFF)
		gl.StencilFunc(gl.ALWAYS, 0xFF, 0xFF)
	case .WriteZeroes:
		gl.StencilMask(0xFF)
		gl.StencilFunc(gl.ALWAYS, 0, 0xFF)
	case .DrawOverOnes:
		gl.StencilMask(0)
		gl.StencilFunc(gl.EQUAL, 0, 0xFF)
	case .DrawOverZeroes:
		gl.StencilMask(0)
		gl.StencilFunc(gl.EQUAL, 0xFF, 0xFF)
	case .Off:
	// should already be handled
	}
}

internal_set_framebuffer_directly :: proc(framebuffer: ^Framebuffer) {
	current_framebuffer = framebuffer

	internal_use_framebuffer(framebuffer)
	if (framebuffer == nil) {
		internal_on_framebuffer_resize(c.int(window_rect.width), c.int(window_rect.height))
	} else {
		internal_on_framebuffer_resize(
			c.int(framebuffer.texture.width),
			c.int(framebuffer.texture.height),
		)
	}
}


set_framebuffer :: proc(framebuffer: ^Framebuffer) {
	if (current_framebuffer == framebuffer) {
		return
	}

	flush()

	internal_set_framebuffer_directly(framebuffer)
}


vertex_2D :: proc(x, y: f32) -> Vertex {
	return Vertex{position = {x, y, 0}, uv = {x, y}}
}

vertex_2D_uv :: proc(x, y: f32, u, v: f32) -> Vertex {
	return Vertex{position = {x, y, 0}, uv = {u, v}}
}

draw_triangle :: proc(output: ^MeshBuffer, v1, v2, v3: Vertex) {
	flush_mesh_buffer_if_not_enough_space(output, 3, 3)

	v1_index := add_vertex_mesh_buffer(output, v1)
	v2_index := add_vertex_mesh_buffer(output, v2)
	v3_index := add_vertex_mesh_buffer(output, v3)

	add_mesh_buffer_triangle(output, v1_index, v2_index, v3_index)
}


draw_triangle_outline :: proc(output: ^MeshBuffer, v1, v2, v3: Vertex, thickness: f32) {
	mean := (v1.position + v2.position + v3.position) / 3.0

	v1_outer := v1
	v1_outer.position = v1.position + (linalg.vector_normalize(v1.position - mean) * thickness)


	v2_outer := v2
	v2_outer.position = v2.position + (linalg.vector_normalize(v2.position - mean) * thickness)

	v3_outer := v3
	v3_outer.position = v3.position + (linalg.vector_normalize(v3.position - mean) * thickness)

	nline := begin_nline_strip(output)
	extend_nline_strip(&nline, v1, v1_outer)
	extend_nline_strip(&nline, v2, v2_outer)
	extend_nline_strip(&nline, v3, v3_outer)
	extend_nline_strip(&nline, v1, v1_outer)
}


draw_quad :: proc(output: ^MeshBuffer, v1, v2, v3, v4: Vertex) {
	flush_mesh_buffer_if_not_enough_space(output, 4, 6)

	v1_index := add_vertex_mesh_buffer(output, v1)
	v2_index := add_vertex_mesh_buffer(output, v2)
	v3_index := add_vertex_mesh_buffer(output, v3)
	v4_index := add_vertex_mesh_buffer(output, v4)

	add_quad_mesh_buffer(output, v1_index, v2_index, v3_index, v4_index)
}

draw_quad_outline :: proc(output: ^MeshBuffer, v1, v2, v3, v4: Vertex, thickness: f32) {
	mean := (v1.position + v2.position + v3.position + v4.position) / 4.0

	v1_outer := v1
	v1_outer.position = v1.position + (linalg.vector_normalize(v1.position - mean) * thickness)


	v2_outer := v2
	v2_outer.position = v2.position + (linalg.vector_normalize(v2.position - mean) * thickness)

	v3_outer := v3
	v3_outer.position = v3.position + (linalg.vector_normalize(v3.position - mean) * thickness)

	v4_outer := v4
	v4_outer.position = v4.position + (linalg.vector_normalize(v4.position - mean) * thickness)

	line := begin_nline_strip(output)
	extend_nline_strip(&line, v1, v1_outer)
	extend_nline_strip(&line, v2, v2_outer)
	extend_nline_strip(&line, v3, v3_outer)
	extend_nline_strip(&line, v4, v4_outer)
	extend_nline_strip(&line, v1, v1_outer)
}

draw_rect :: proc(output: ^MeshBuffer, rect: Rect) {
	v1 := vertex_2D_uv(rect.x0, rect.y0, 0, 0)
	v2 := vertex_2D_uv(rect.x0, rect.y0 + rect.height, 0, 1)
	v3 := vertex_2D_uv(rect.x0 + rect.width, rect.y0 + rect.height, 1, 1)
	v4 := vertex_2D_uv(rect.x0 + rect.width, rect.y0, 1, 0)

	draw_quad(output, v1, v2, v3, v4)
}

draw_rect_uv :: proc(output: ^MeshBuffer, rect: Rect, uv: Rect) {
	v1 := vertex_2D_uv(rect.x0, rect.y0, uv.x0, uv.y0)
	v2 := vertex_2D_uv(rect.x0, rect.y0 + rect.height, uv.x0, uv.y0 + uv.height)
	v3 := vertex_2D_uv(
		rect.x0 + rect.width,
		rect.y0 + rect.height,
		uv.x0 + uv.width,
		uv.y0 + uv.height,
	)
	v4 := vertex_2D_uv(rect.x0 + rect.width, rect.y0, uv.x0 + uv.width, uv.y0)

	draw_quad(output, v1, v2, v3, v4)
}

draw_rect_outline :: proc(output: ^MeshBuffer, rect: Rect, thickness: f32) {
	using rect
	x1 := x0 + width
	y1 := y0 + height


	// the outline is broken into 4 smaller rects like this:
	// 322222222
	// 3       4
	// 3       4
	// 111111114

	draw_rect(output, {x0 - thickness, y0 - thickness, width + thickness, thickness})
	draw_rect(output, {x0, y1, width + thickness, thickness})
	draw_rect(output, {x0 - thickness, y0, thickness, height + thickness})
	draw_rect(output, {x1, y0 - thickness, thickness, height + thickness})
}

arc_edge_count :: proc(
	radius: f32,
	angle: f32 = math.TAU,
	max_circle_edge_count: int = 64,
	points_per_pixel: f32 = 4,
) -> int {
	// Circumferance C = radius * angle.
	// If we want 1 point every x units of circumferance, then num_points = C / x. 
	// We would break the angle down into angle / (num_points) to get the delta_angle.
	// So, delta_angle = angle / (num_points) = angle / ((radius * angle) / x) = (angle * x) / (radius * angle) = x / radius
	delta_angle := points_per_pixel / radius

	edge_count := min(int(angle / delta_angle) + 1, max_circle_edge_count)

	return edge_count
}


draw_arc :: proc(
	output: ^MeshBuffer,
	x_center, y_center, radius, start_angle, end_angle: f32,
	edge_count: int,
) {
	ngon := begin_ngon(output)
	center := vertex_2D(x_center, y_center)
	extend_ngon(&ngon, center)

	delta_angle := (end_angle - start_angle) / f32(edge_count)
	for angle := end_angle; angle > start_angle - delta_angle + 0.001; angle -= delta_angle {
		x := x_center + radius * math.cos(angle)
		y := y_center + radius * math.sin(angle)

		v := vertex_2D(x, y)
		extend_ngon(&ngon, v)
	}
}


draw_arc_outline :: proc(
	output: ^MeshBuffer,
	x_center, y_center, radius, start_angle, end_angle: f32,
	edge_count: int,
	thickness: f32,
) {
	if (edge_count < 0) {
		return
	}

	delta_angle := (end_angle - start_angle) / f32(edge_count)

	nline := begin_nline_strip(output)
	for angle := end_angle; angle > start_angle - delta_angle + 0.001; angle -= delta_angle {
		sin_angle := math.sin(angle)
		cos_angle := math.cos(angle)

		X1 := x_center + radius * cos_angle
		Y1 := y_center + radius * sin_angle

		X2 := x_center + (radius + thickness) * cos_angle
		Y2 := y_center + (radius + thickness) * sin_angle

		v1 := vertex_2D(X1, Y1)
		v2 := vertex_2D(X2, Y2)
		extend_nline_strip(&nline, v1, v2)
	}
}

draw_circle :: proc(output: ^MeshBuffer, x0, y0, r: f32, edges: int) {
	draw_arc(output, x0, y0, r, 0, math.TAU, edges)
}

draw_circle_outline :: proc(output: ^MeshBuffer, x0, y0, r: f32, edges: int, thickness: f32) {
	draw_arc_outline(output, x0, y0, r, 0, math.TAU, edges, thickness)
}


CapType :: enum {
	None,
	Circle,
}


draw_line :: proc(
	output: ^MeshBuffer,
	x0, y0: f32,
	x1, y1: f32,
	thickness: f32,
	cap_type: CapType,
) {
	draw_cap :: proc(output: ^MeshBuffer, x0, y0, angle, thickness: f32, cap_type: CapType) {
		switch cap_type {
		case .None:
		// do nothing
		case .Circle:
			edge_count := arc_edge_count(thickness, math.PI, 64)
			draw_arc(
				output,
				x0,
				y0,
				thickness,
				angle - math.PI / 2,
				angle + math.PI / 2,
				edge_count,
			)
		}
	}

	thickness := thickness
	thickness /= 2

	dirX := x1 - x0
	dirY := y1 - y0
	mag := math.sqrt(dirX * dirX + dirY * dirY)

	perpX := -thickness * dirY / mag
	perpY := thickness * dirX / mag

	v1 := vertex_2D(x0 + perpX, y0 + perpY)
	v2 := vertex_2D(x0 - perpX, y0 - perpY)
	v3 := vertex_2D(x1 - perpX, y1 - perpY)
	v4 := vertex_2D(x1 + perpX, y1 + perpY)
	draw_quad(output, v1, v2, v3, v4)

	startAngle := math.atan2(dirY, dirX)
	draw_cap(output, x0, y0, startAngle - math.PI, thickness, cap_type)
	draw_cap(output, x1, y1, startAngle, thickness, cap_type)
}


draw_line_outline :: proc(
	output: ^MeshBuffer,
	x0, y0: f32,
	x1, y1: f32,
	thickness: f32,
	cap_type: CapType,
	outline_thicknes: f32,
) {
	draw_cap_outline :: proc(
		output: ^MeshBuffer,
		x0, y0, angle, thickness: f32,
		cap_type: CapType,
		outline_thickness: f32,
	) {
		switch (cap_type) {
		case .None:
			line_vec_x := math.cos(angle)
			line_vec_y := math.sin(angle)

			line_vec_perp_x := -line_vec_y
			line_vec_perp_y := line_vec_x

			p1_inner_x := x0 + -line_vec_perp_x * (thickness + outline_thickness)
			p2_inner_x := x0 + line_vec_perp_x * (thickness + outline_thickness)
			p1_inner_y := y0 + -line_vec_perp_y * (thickness + outline_thickness)
			p2_inner_y := y0 + line_vec_perp_y * (thickness + outline_thickness)

			p1_outer_x := p1_inner_x + line_vec_x * outline_thickness
			p2_outer_x := p2_inner_x + line_vec_x * outline_thickness
			p1_outer_y := p1_inner_y + line_vec_y * outline_thickness
			p2_outer_y := p2_inner_y + line_vec_y * outline_thickness

			draw_quad(
				output,
				vertex_2D(p1_inner_x, p1_inner_y),
				vertex_2D(p1_outer_x, p1_outer_y),
				vertex_2D(p2_outer_x, p2_outer_y),
				vertex_2D(p2_inner_x, p2_inner_y),
			)
		case .Circle:
			edge_count := arc_edge_count(thickness, math.PI, 64)
			draw_arc_outline(
				output,
				x0,
				y0,
				thickness,
				angle - math.PI / 2,
				angle + math.PI / 2,
				edge_count,
				outline_thickness,
			)
		}
	}

	thickness := thickness
	thickness /= 2

	dirX := x1 - x0
	dirY := y1 - y0
	mag := math.sqrt(dirX * dirX + dirY * dirY)

	perpXInner := -(thickness) * dirY / mag
	perpYInner := (thickness) * dirX / mag

	perpXOuter := -(thickness + outline_thicknes) * dirY / mag
	perpYOuter := (thickness + outline_thicknes) * dirX / mag

	// draw quad on one side of the line
	vInner := vertex_2D_uv(x0 + perpXInner, y0 + perpYInner, perpXInner, perpYInner)
	vOuter := vertex_2D_uv(x0 + perpXOuter, y0 + perpYOuter, perpXOuter, perpYOuter)
	v1Inner := vertex_2D_uv(x1 + perpXInner, y1 + perpYInner, perpXInner, perpYInner)
	v1Outer := vertex_2D_uv(x1 + perpXOuter, y1 + perpYOuter, perpXOuter, perpYOuter)
	draw_quad(output, vInner, vOuter, v1Outer, v1Inner)

	// draw quad on other side of the line
	vInner = vertex_2D_uv(x0 - perpXInner, y0 - perpYInner, -perpXInner, -perpYInner)
	vOuter = vertex_2D_uv(x0 - perpXOuter, y0 - perpYOuter, perpXOuter, perpYOuter)
	v1Inner = vertex_2D_uv(x1 - perpXInner, y1 - perpYInner, -perpXInner, -perpYInner)
	v1Outer = vertex_2D_uv(x1 - perpXOuter, y1 - perpYOuter, -perpXOuter, -perpYOuter)
	draw_quad(output, vInner, vOuter, v1Outer, v1Inner)

	// Draw both caps
	startAngle := math.atan2(dirY, dirX)
	draw_cap_outline(output, x0, y0, startAngle - math.PI, thickness, cap_type, outline_thicknes)
	draw_cap_outline(output, x1, y1, startAngle, thickness, cap_type, outline_thicknes)
}


DrawFontTextMeasureResult :: struct {
	width: f32,
}

draw_font_text :: proc(
	output: ^MeshBuffer,
	font: ^DrawableFont,
	text: string,
	size, x, y: f32,
	pos: int = 0,
	is_measuring := false,
) -> DrawFontTextMeasureResult {
	prev_texture := current_texture
	if !is_measuring {
		set_texture(font.texture)
	}

	pos := pos
	init_x := x
	x := x
	for pos < len(text) {
		codepoint, codepoint_size := utf8_next_rune(text, pos)
		pos += codepoint_size

		glyph_info := get_font_glyph_info(font, codepoint)

		if !is_measuring {
			draw_font_glyph(output, font, glyph_info, size, x, y)
		}

		x += glyph_info.advance_x * size
	}

	if !is_measuring {
		set_texture(prev_texture)
	}

	return DrawFontTextMeasureResult{width = x - init_x}
}

get_font_glyph_info :: proc(font: ^DrawableFont, codepoint: rune) -> GlyphInfo {
	slot := internal_font_rune_is_loaded(font, codepoint)
	if slot == -1 {
		flush()
		slot = internal_font_load_rune(font, codepoint)
	}

	if slot == -1 {
		if codepoint == '?' {
			debug_log(
				"Font did not contain the '?' code point, which is requried when handling unknown code points",
				severity = .FatalError,
			)
			return GlyphInfo{}
		}

		return get_font_glyph_info(font, '?')
	}

	glyph_info := font.glyph_slots[slot]
	return glyph_info
}

// NOTE: this function does not start using the font's texture. You will need to do that manually
draw_font_glyph :: proc(
	output: ^MeshBuffer,
	font: ^DrawableFont,
	glyph_info: GlyphInfo,
	size, x, y: f32,
) {
	rect := Rect{
		x + glyph_info.offset.x * size,
		y + glyph_info.offset.y * size,
		glyph_info.size.x * size,
		glyph_info.size.y * size,
	}
	uv := glyph_info.uv
	draw_rect_uv(output, rect, uv)
}


// -------- Keyboard input --------


key_was_down :: proc(key: KeyCode) -> bool {
	if key == .Unknown {
		return false
	}

	return keyboard_state_prev[int(key)]
}

key_is_down :: proc(key: KeyCode) -> bool {
	if key == .Unknown {
		return false
	}

	return keyboard_state_curr[int(key)]
}

key_just_pressed :: proc(key: KeyCode) -> bool {
	return (!key_was_down(key)) && key_is_down(key)
}

key_just_released :: proc(key: KeyCode) -> bool {
	return key_was_down(key) && (!key_is_down(key))
}

@(private)
internal_update_key_inputs_before_poll :: proc() {
	inputted_runes_count = 0
	keys_just_pressed_count = 0
}

@(private)
internal_update_key_input :: proc() {
	was_any_down = is_any_down
	is_any_down = false

	check_key :: proc(key: KeyCode) -> bool {
		return glfw.GetKey(window, c.int(key)) == glfw.PRESS
	}

	for i in 0 ..< int(KeyCode_Max) {
		keyboard_state_prev[i] = keyboard_state_curr[i]

		key := KeyCode(i)
		is_down := false

		// TODO: report this bug in ols. I shouldn't need to put #partial here
		#partial switch key {
		case .Ctrl:
			is_down = check_key(.LeftCtrl) || check_key(.RightCtrl)
		case .Shift:
			is_down = check_key(.LeftShift) || check_key(.RightShift)
		case .Alt:
			is_down = check_key(.LeftAlt) || check_key(.RightAlt)
		case:
			is_down = check_key(key)
		}

		keyboard_state_curr[key] = is_down
	}
}

// we are kinda just assuming these are 0, 1, 2
mouse_button_is_down :: proc(mb: MBCode) -> bool {
	return mouse_button_states[mb]
}

mouse_button_was_down :: proc(mb: MBCode) -> bool {
	return prev_mouse_button_states[mb]
}

mouse_button_just_pressed :: proc(b: MBCode) -> bool {
	return !mouse_button_was_down(b) && mouse_button_is_down(b)
}

mouse_button_just_released :: proc(b: MBCode) -> bool {
	return mouse_button_was_down(b) && !mouse_button_is_down(b)
}

get_mouse_pos :: proc() -> Vec2 {
	return(
		Vec2{
			internal_mouse_position.x - layout_rect.x0,
			internal_mouse_position.y - layout_rect.y0,
		} \
	)
}

set_mouse_position :: proc(pos: Vec2) {
	glfw.SetCursorPos(window, f64(pos.x), f64(pos.y))
}

internal_glfw_scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	incoming_mouse_wheel_notches += f32(xoffset)
}

mouse_is_over :: proc(rect: Rect) -> bool {
	pos := get_mouse_pos()
	x := pos[0]
	y := pos[1]

	left := rect.x0
	right := rect.x0 + rect.width
	top := rect.y0 + rect.height
	bottom := rect.y0

	return (x > left && x < right) && (y < top && y > bottom)
}

internal_update_mouse_input :: proc() {
	for i in MBCode {
		prev_mouse_button_states[i] = mouse_button_states[i]
	}

	mouse_wheel_notches = incoming_mouse_wheel_notches
	incoming_mouse_wheel_notches = 0

	mouse_was_any_down = mouse_any_down
	mouse_any_down = false
	for i in MBCode {
		state := glfw.GetMouseButton(window, c.int(i)) == glfw.PRESS
		mouse_button_states[i] = state
		mouse_any_down = mouse_any_down || state
	}

	internal_prev_mouse_position = internal_mouse_position
	x, y := glfw.GetCursorPos(window)
	internal_mouse_position.x = f32(x)
	internal_mouse_position.y = framebuffer_rect.height - f32(y)
	mouse_delta.x = internal_mouse_position.x - internal_prev_mouse_position.x
	mouse_delta.y = internal_mouse_position.y - internal_prev_mouse_position.y
}
