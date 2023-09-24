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

target_fps: int
window: glfw.WindowHandle
last_frame_time, delta_time: f64
layout_rect: Rect

window_rect: Rect // NOTE: x0, y0 are always zero. 
framebuffer_rect: Rect

// Render state

white_pixel_texture: ^Texture
mb_im: ^MeshBuffer // use this mesh buffer to render things in an immediate mode style
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

// (\w+) (\*?)([\w_]+)

GetTime :: proc() -> f64 {
	return glfw.GetTime()
}

SetTime :: proc(t: f64) {
	glfw.SetTime(t)

	glfw.SetCharCallback(nil, internal_glfw_character_callback)
}

VW :: proc() -> f32 {
	return layout_rect.width
}

VH :: proc() -> f32 {
	return layout_rect.height
}

SetTargetFPS :: proc(fps: int) {
	target_fps = fps
}

WindowShouldClose :: proc() -> bool {
	return glfw.WindowShouldClose(window) == true
}


internal_glfw_character_callback :: proc "c" (window: glfw.WindowHandle, r: rune) {
	if (inputted_runes_count >= len(inputted_runes)) {
		context = runtime.default_context()
		DebugLog("WARNING - text buffer is full")
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
		DebugLog("WARNING - key input buffer is full")
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

	SetLayoutRect(layout_rect, false)
	gl.Viewport(0, 0, width, height)
}


internal_SetTextureDirectly :: proc(texture: ^Texture) {
	texture := texture
	if (texture == nil) {
		texture = white_pixel_texture
	}

	Texture_SetTextureUnit(gl.TEXTURE0)
	Texture_Use(texture)
	current_texture = texture
}

SetTexture :: proc(texture: ^Texture) {
	if (texture == current_texture) {
		return
	}

	Flush()
	internal_SetTextureDirectly(texture)
}

GetTexture :: proc() -> ^Texture {
	return current_texture
}

ClearScreen :: proc(col: Color) {
	gl.StencilMask(1)
	gl.ClearColor(col.r, col.g, col.b, col.a)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)
}

Flush :: proc() {
	MeshBuffer_Flush(mb_im)
}

SetLayoutRect :: proc(rect: Rect, clip: bool) {
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

	SetViewProjection_Cartesian2D(rect.x0, rect.y0, 1, 1)
}

Init :: proc(width: int, height: int, title: string) -> bool {
	DebugLog("Initializing window '%s' ... ", title)
	{
		if (!bool(glfw.Init())) {
			DebugLog("glfw failed to initialize")
			return false
		}

		current_title := strings.clone_to_cstring(title)
		defer delete(current_title)
		window = glfw.CreateWindow(c.int(width), c.int(height), current_title, nil, nil)
		if (window == nil) {
			DebugLog("glfw failed to create a window")
			glfw.Terminate()
			return false
		}

		/* Make the window's context current */
		glfw.MakeContextCurrent(window)

		glfw.SetScrollCallback(window, internal_glfw_scroll_callback)
		glfw.SetKeyCallback(window, internal_glfw_key_callback)
		glfw.SetCharCallback(window, internal_glfw_character_callback)
		glfw.SetFramebufferSizeCallback(window, internal_glfw_framebuffer_size_callback)

		DebugLog("GLFW initialized\n")
	}


	DebugLog("Initializing Rendering ... ")
	{
		gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)

		mb_im = MeshBuffer_Make(2000, 6000)
		internal_shader = Shader_MakeDefaultShader()
		SetCurrentShader(internal_shader)

		gl.Enable(gl.BLEND)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

		gl.Enable(gl.STENCIL_TEST)
		gl.StencilFunc(gl.EQUAL, 0, 0xFF)

		gl.Enable(gl.DEPTH_TEST)

		SetBackfaceCulling(false)

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
			white_pixel_texture = Texture_FromImage(&img)

			white_pixel_texture.filtering = gl.NEAREST
			Texture_ApplySettings(white_pixel_texture)
		}

		DebugLog(
			"OpenGL initialized. OpenGL info: %s, Version: %s",
			gl.GetString(gl.VENDOR),
			gl.GetString(gl.VERSION),
		)
	}

	// Text_Init()
	return true
}

BeginFrame :: proc() {
	internal_UpdateKeyInputsBeforePoll()
	glfw.PollEvents()
	internal_UpdateMouseInput()
	internal_UpdateKeyInput()

	w, h := glfw.GetWindowSize(window)
	window_rect.width = f32(w)
	window_rect.height = f32(h)

	SetTransform(linalg.MATRIX4F32_IDENTITY)
	internal_SetTextureDirectly(nil)
	internal_UseFramebufferDirectly(nil)

	SetLayoutRect(window_rect, false)
}

EndFrame :: proc() {
	Flush()
	UseFramebuffer(nil)
	glfw.SwapBuffers(window)

	frame_end := GetTime()
	delta_time = frame_end - last_frame_time

	if (target_fps == 0) {
		last_frame_time = frame_end
		return
	}

	// This is a power saving mechanism that will sleep the thread if we
	// have the time available to do so. It should reduce the overall CPU consumption.

	frame_duration := 1 / f64(target_fps)
	time_to_next_frame := frame_duration - delta_time
	if (time_to_next_frame > 0) {
		nanoseconds := i64(time_to_next_frame * 1000000000)
		time.sleep(time.Duration(nanoseconds))

		frame_end = GetTime()
		delta_time = frame_end - last_frame_time
	}

	last_frame_time = frame_end
}

UnInit :: proc() {
	DebugLog("UnInitializing...")

	// free rendering resources
	Shader_Free(internal_shader)
	MeshBuffer_Free(mb_im)
	Texture_Free(white_pixel_texture)

	glfw.Terminate()

	DebugLog("Done")
}

SetViewProjection_Cartesian2D :: proc(x, y, sx, sy: f32) {
	width := sx * framebuffer_rect.width
	height := sy * framebuffer_rect.height

	translation := Vec3{x - width / 2, y - height / 2, 0}
	view := linalg.matrix4_translate(translation)

	scale := Vec3{2 / width, 2 / height, 1}
	projection := linalg.matrix4_scale(scale)

	SetView(view)
	SetProjection(projection)

    gl.DepthFunc(gl.LEQUAL);
}

GetLookAtMat4 :: proc(position: Vec3, target: Vec3, up: Vec3) -> Mat4 {
	return linalg.matrix4_look_at_f32(position, target, up)
}

GetOrientationMat4 :: proc(position: Vec3, rotation: Quat) -> Mat4 {
	view := linalg.mul(
		linalg.matrix4_from_quaternion(rotation),
		linalg.matrix4_translate(position),
	)
	return view
}

GetPerspectiveMat4 :: proc(fovy, aspect, depth_near, depth_far, center_x, center_y: f32) -> Mat4 {
	projection := linalg.matrix4_perspective_f32(fovy, aspect, depth_near, depth_far)
	screenCenter := linalg.matrix4_translate_f32(Vec3{center_x / VW(), center_y / VH(), 0})
	scale := linalg.matrix4_scale_f32(Vec3{-1, 1, 1})

	return linalg.mul(linalg.mul(projection, screenCenter), scale)
}

GetOrthographicMat4 :: proc(
	width, height, depth_near, depth_far, center_x, center_y: f32,
) -> Mat4 {
	projection := linalg.matrix_ortho3d_f32(
		center_x - width * 0.5,
		center_x + width * 0.5,
		center_y - 0.5 * height,
		center_y + 0.5 * height,
		depth_near,
		depth_far,
	)
	screenCenter := linalg.matrix4_translate_f32(Vec3{center_x / VW(), center_y / VH(), 0})
	scale := linalg.matrix4_scale_f32(Vec3{-1, 1, 1})

	return linalg.mul(linalg.mul(projection, screenCenter), scale)
}


SetProjection :: proc(mat: Mat4) {
	Flush()

	projection = mat
	Shader_SetMatrix4(current_shader.projection_loc, &projection)
}

SetTransform :: proc(mat: Mat4) {
	Flush()

	transform = mat
	Shader_SetMatrix4(current_shader.transform_loc, &transform)
}

SetView :: proc(mat: Mat4) {
	Flush()

	view = mat
	Shader_SetMatrix4(current_shader.view_loc, &view)
}

SetDrawColor :: proc(color: Color) {
	Flush()

	draw_color = color
	Shader_SetVector4(current_shader.color_loc, draw_color)
}

SetBackfaceCulling :: proc(state: bool) {
	Flush()

	if (state) {
		gl.Enable(gl.CULL_FACE)
	} else {
		gl.Disable(gl.CULL_FACE)
	}
}

SetCurrentShader :: proc(shader: ^Shader) {
	shader := shader
	if (shader == nil) {
		shader = internal_shader
	}

	Flush()

	current_shader = shader
	internal_Shader_Use(current_shader)
	Shader_SetMatrix4(current_shader.transform_loc, &transform)
	Shader_SetMatrix4(current_shader.view_loc, &view)
	Shader_SetMatrix4(current_shader.projection_loc, &projection)
}

StencilBegin :: proc(can_draw: bool, inverse_stencil: bool) {
	Flush()

	if (!can_draw) {
		gl.ColorMask(false, false, false, false)
	}

	if (inverse_stencil) {
		gl.ClearStencil(1)
	} else {
		gl.ClearStencil(0)
	}

	gl.StencilMask(1)
	gl.Clear(gl.STENCIL_BUFFER_BIT)

	gl.Enable(gl.STENCIL_TEST)
	gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE)

	if (inverse_stencil) {
		gl.StencilFunc(gl.ALWAYS, 0, 0)
	} else {
		gl.StencilFunc(gl.ALWAYS, 1, 1)
	}
}

StencilUse :: proc() {
	Flush()

	gl.ColorMask(true, true, true, true)
	gl.StencilFunc(gl.NOTEQUAL, 1, 1)
	gl.StencilMask(0)
}

StencilEnd :: proc() {
	Flush()

	gl.Disable(gl.STENCIL_TEST)
}

internal_UseFramebufferDirectly :: proc(framebuffer: ^Framebuffer) {
	current_framebuffer = framebuffer

	if (framebuffer == nil) {
		Framebuffer_StopUsing()
		internal_on_framebuffer_resize(c.int(window_rect.width), c.int(window_rect.height))
	} else {
		Framebuffer_Use(framebuffer)
		internal_on_framebuffer_resize(
			c.int(framebuffer.texture.width),
			c.int(framebuffer.texture.height),
		)
	}
}


UseFramebuffer :: proc(framebuffer: ^Framebuffer) {
	if (current_framebuffer == framebuffer) {
		return
	}

	Flush()

	internal_UseFramebufferDirectly(framebuffer)
}


GetVertex2D :: proc(x, y: f32) -> Vertex {
	return Vertex{position = {x, y, 0}, uv = {x, y}}
}

GetVertex2DUV :: proc(x, y: f32, u, v: f32) -> Vertex {
	return Vertex{position = {x, y, 0}, uv = {u, v}}
}

DrawTriangle :: proc(output: ^MeshBuffer, v1, v2, v3: Vertex) {
	MeshBuffer_FlushIfNotEnoughSpace(output, 3, 3)

	v1_index := MeshBuffer_AddVertex(output, v1)
	v2_index := MeshBuffer_AddVertex(output, v2)
	v3_index := MeshBuffer_AddVertex(output, v3)

	MeshBuffer_AddTriangle(output, v1_index, v2_index, v3_index)
}


DrawTriangleOutline :: proc(output: ^MeshBuffer, v1, v2, v3: Vertex, thickness: f32) {
	mean := (v1.position + v2.position + v3.position) / 3.0

	v1_outer := v1
	v1_outer.position = v1.position + (linalg.vector_normalize(v1.position - mean) * thickness)


	v2_outer := v2
	v2_outer.position = v2.position + (linalg.vector_normalize(v2.position - mean) * thickness)

	v3_outer := v3
	v3_outer.position = v3.position + (linalg.vector_normalize(v3.position - mean) * thickness)

	nline := NLineStrip_Begin(output)
	NLineStrip_Extend(&nline, v1, v1_outer)
	NLineStrip_Extend(&nline, v2, v2_outer)
	NLineStrip_Extend(&nline, v3, v3_outer)
	NLineStrip_Extend(&nline, v1, v1_outer)
}


DrawQuad :: proc(output: ^MeshBuffer, v1, v2, v3, v4: Vertex) {
	MeshBuffer_FlushIfNotEnoughSpace(output, 4, 6)

	v1_index := MeshBuffer_AddVertex(output, v1)
	v2_index := MeshBuffer_AddVertex(output, v2)
	v3_index := MeshBuffer_AddVertex(output, v3)
	v4_index := MeshBuffer_AddVertex(output, v4)

	MeshBuffer_AddQuad(output, v1_index, v2_index, v3_index, v4_index)
}

DrawQuadOutline :: proc(output: ^MeshBuffer, v1, v2, v3, v4: Vertex, thickness: f32) {
	mean := (v1.position + v2.position + v3.position + v4.position) / 4.0

	v1_outer := v1
	v1_outer.position = v1.position + (linalg.vector_normalize(v1.position - mean) * thickness)


	v2_outer := v2
	v2_outer.position = v2.position + (linalg.vector_normalize(v2.position - mean) * thickness)

	v3_outer := v3
	v3_outer.position = v3.position + (linalg.vector_normalize(v3.position - mean) * thickness)

	v4_outer := v4
	v4_outer.position = v4.position + (linalg.vector_normalize(v4.position - mean) * thickness)

	line := NLineStrip_Begin(output)
	NLineStrip_Extend(&line, v1, v1_outer)
	NLineStrip_Extend(&line, v2, v2_outer)
	NLineStrip_Extend(&line, v3, v3_outer)
	NLineStrip_Extend(&line, v4, v4_outer)
	NLineStrip_Extend(&line, v1, v1_outer)
}

DrawRect :: proc(output: ^MeshBuffer, rect: Rect) {
	v1 := GetVertex2DUV(rect.x0, rect.y0, 0, 0)
	v2 := GetVertex2DUV(rect.x0, rect.y0 + rect.height, 0, 1)
	v3 := GetVertex2DUV(rect.x0 + rect.width, rect.y0 + rect.height, 1, 1)
	v4 := GetVertex2DUV(rect.x0 + rect.width, rect.y0, 1, 0)

	DrawQuad(output, v1, v2, v3, v4)
}

DrawRectOutline :: proc(output: ^MeshBuffer, rect: Rect, thickness: f32) {
	using rect
	x1 := x0 + width
	y1 := y0 + height


	// the outline is broken into 4 smaller rects like this:
	// 322222222
	// 3       4
	// 3       4
	// 111111114

	DrawRect(output, {x0 - thickness, y0 - thickness, width + thickness, thickness})
	DrawRect(output, {x0, y1, width + thickness, thickness})
	DrawRect(output, {x0 - thickness, y0, thickness, height + thickness})
	DrawRect(output, {x1, y0 - thickness, thickness, height + thickness})
}

GetEdgeCountForArc :: proc(
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


DrawArc :: proc(
	output: ^MeshBuffer,
	x_center, y_center, radius, start_angle, end_angle: f32,
	edge_count: int,
) {
	ngon := NGon_Begin(output)
	center := GetVertex2D(x_center, y_center)
	NGon_Extend(&ngon, center)

	delta_angle := (end_angle - start_angle) / f32(edge_count)
	for angle := end_angle; angle > start_angle - delta_angle + 0.001; angle -= delta_angle {
		x := x_center + radius * math.cos(angle)
		y := y_center + radius * math.sin(angle)

		v := GetVertex2D(x, y)
		NGon_Extend(&ngon, v)
	}
}


DrawArcOutline :: proc(
	output: ^MeshBuffer,
	x_center, y_center, radius, start_angle, end_angle: f32,
	edge_count: int,
	thickness: f32,
) {
	if (edge_count < 0) {
		return
	}

	delta_angle := (end_angle - start_angle) / f32(edge_count)

	nline := NLineStrip_Begin(output)
	for angle := end_angle; angle > start_angle - delta_angle + 0.001; angle -= delta_angle {
		sin_angle := math.sin(angle)
		cos_angle := math.cos(angle)

		X1 := x_center + radius * cos_angle
		Y1 := y_center + radius * sin_angle

		X2 := x_center + (radius + thickness) * cos_angle
		Y2 := y_center + (radius + thickness) * sin_angle

		v1 := GetVertex2D(X1, Y1)
		v2 := GetVertex2D(X2, Y2)
		NLineStrip_Extend(&nline, v1, v2)
	}
}

DrawCircle :: proc(output: ^MeshBuffer, x0, y0, r: f32, edges: int) {
	DrawArc(output, x0, y0, r, 0, math.TAU, edges)
}

DrawCircleOutline :: proc(output: ^MeshBuffer, x0, y0, r: f32, edges: int, thickness: f32) {
	DrawArcOutline(output, x0, y0, r, 0, math.TAU, edges, thickness)
}


CapType :: enum {
	None,
	Circle,
}

DrawLine__DrawCap :: proc(output: ^MeshBuffer, x0, y0, angle, thickness: f32, cap_type: CapType) {
	switch cap_type {
	case .None:
	// do nothing
	case .Circle:
		edge_count := GetEdgeCountForArc(thickness, math.PI, 64)
		DrawArc(output, x0, y0, thickness, angle - math.PI / 2, angle + math.PI / 2, edge_count)
	}
}

DrawLineOutline__DrawCapOutline :: proc(
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

		DrawQuad(
			output, 
			GetVertex2D(p1_inner_x, p1_inner_y),
			GetVertex2D(p1_outer_x, p1_outer_y),
			GetVertex2D(p2_outer_x, p2_outer_y),
			GetVertex2D(p2_inner_x, p2_inner_y),
		);
	case .Circle:
		edge_count := GetEdgeCountForArc(thickness, math.PI, 64)
		DrawArcOutline(
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

DrawLine :: proc(
	output: ^MeshBuffer,
	x0, y0: f32,
	x1, y1: f32,
	thickness: f32,
	cap_type: CapType,
) {
	thickness := thickness
	thickness /= 2

	dirX := x1 - x0
	dirY := y1 - y0
	mag := math.sqrt(dirX * dirX + dirY * dirY)

	perpX := -thickness * dirY / mag
	perpY := thickness * dirX / mag

	v1 := GetVertex2D(x0 + perpX, y0 + perpY)
	v2 := GetVertex2D(x0 - perpX, y0 - perpY)
	v3 := GetVertex2D(x1 - perpX, y1 - perpY)
	v4 := GetVertex2D(x1 + perpX, y1 + perpY)
	DrawQuad(output, v1, v2, v3, v4)

	startAngle := math.atan2(dirY, dirX)
	DrawLine__DrawCap(output, x0, y0, startAngle - math.PI, thickness, cap_type)
	DrawLine__DrawCap(output, x1, y1, startAngle, thickness, cap_type)
}


DrawLineOutline :: proc(
	output: ^MeshBuffer,
	x0, y0: f32,
	x1, y1: f32,
	thickness: f32,
	cap_type: CapType,
	outline_thicknes: f32,
) {
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
	vInner := GetVertex2DUV(x0 + perpXInner, y0 + perpYInner, perpXInner, perpYInner)
	vOuter := GetVertex2DUV(x0 + perpXOuter, y0 + perpYOuter, perpXOuter, perpYOuter)
	v1Inner := GetVertex2DUV(x1 + perpXInner, y1 + perpYInner, perpXInner, perpYInner)
	v1Outer := GetVertex2DUV(x1 + perpXOuter, y1 + perpYOuter, perpXOuter, perpYOuter)
	DrawQuad(output, vInner, vOuter, v1Outer, v1Inner)

	// draw quad on other side of the line
	vInner = GetVertex2DUV(x0 - perpXInner, y0 - perpYInner, -perpXInner, -perpYInner)
	vOuter = GetVertex2DUV(x0 - perpXOuter, y0 - perpYOuter, perpXOuter, perpYOuter)
	v1Inner = GetVertex2DUV(x1 - perpXInner, y1 - perpYInner, -perpXInner, -perpYInner)
	v1Outer = GetVertex2DUV(x1 - perpXOuter, y1 - perpYOuter, -perpXOuter, -perpYOuter)
	DrawQuad(output, vInner, vOuter, v1Outer, v1Inner)

	// Draw both caps
	startAngle := math.atan2(dirY, dirX)
	DrawLineOutline__DrawCapOutline(
		output,
		x0,
		y0,
		startAngle - math.PI,
		thickness,
		cap_type,
		outline_thicknes,
	)
	DrawLineOutline__DrawCapOutline(
		output,
		x1,
		y1,
		startAngle,
		thickness,
		cap_type,
		outline_thicknes,
	)
}


// -------- Keyboard input --------


KeyWasDown :: proc(key: KeyCode) -> bool {
	if key == .Unknown {
		return false
	}

	return keyboard_state_prev[int(key)]
}

KeyIsDown :: proc(key: KeyCode) -> bool {
	if key == .Unknown {
		return false
	}

	return keyboard_state_curr[int(key)]
}

KeyJustPressed :: proc(key: KeyCode) -> bool {
	return (!KeyWasDown(key)) && KeyIsDown(key)
}

KeyJustReleased :: proc(key: KeyCode) -> bool {
	return KeyWasDown(key) && (!KeyIsDown(key))
}

@(private)
internal_UpdateKeyInputsBeforePoll :: proc() {
	inputted_runes_count = 0
	keys_just_pressed_count = 0
}

@(private)
internal_UpdateKeyInput :: proc() {
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

GetMouseScroll :: proc() -> f32 {
	return mouse_wheel_notches
}

// we are kinda just assuming these are 0, 1, 2
MouseButtonIsDown :: proc(mb: MBCode) -> bool {
	return mouse_button_states[mb]
}

MouseButtonWasDown :: proc(mb: MBCode) -> bool {
	return prev_mouse_button_states[mb]
}

MouseButtonJustPressed :: proc(b: MBCode) -> bool {
	return !MouseButtonWasDown(b) && MouseButtonIsDown(b)
}

MouseButtonJustReleased :: proc(b: MBCode) -> bool {
	return MouseButtonWasDown(b) && !MouseButtonIsDown(b)
}

GetMousePos :: proc() -> Vec2 {
	return(
		Vec2{
			internal_mouse_position.x - layout_rect.x0,
			internal_mouse_position.y - layout_rect.y0,
		} \
	)
}

SetMousePosition :: proc(pos: Vec2) {
	glfw.SetCursorPos(window, f64(pos.x), f64(pos.y))
}

GetMouseDelta :: proc() -> Vec2 {
	return mouse_delta
}

internal_glfw_scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	incoming_mouse_wheel_notches += f32(xoffset)
}

MouseIsOver :: proc(rect: Rect) -> bool {
	pos := GetMousePos()
	x := pos[0]
	y := pos[1]

	left := rect.x0
	right := rect.x0 + rect.width
	top := rect.y0 + rect.height
	bottom := rect.y0

	return (x > left && x < right) && (y < top && y > bottom)
}

internal_UpdateMouseInput :: proc() {
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
