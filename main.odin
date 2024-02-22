/**

Current progress:

- [x] Stencil test
- [x] Perspective camera test
- [x] Texture test
- [x] Keyboard input test
- [x] Text rendering 
	- [] Allow specifying fonts to fall back on when unicode chars are missing
	- [] Text shaping w harfbuzz or similar

*/


package main

import "af"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"

randf :: proc() -> f32 {
	return rand.float32()
}


line_benchmark_line_amount := 200
line_benchmark_thickness :: 5

verts_uploaded, indices_uploaded: uint

benchmark_fps_tracker: af.FpsTracker
draw_benchmark_test :: proc() {
	rand.set_global_seed(0)
	if (af.track_fps(&benchmark_fps_tracker, 1, af.delta_time)) {
		// try to figure out how many lines we need to draw to get 60 fps.
		// we are assuming there is a linear relationship between 'line_benchmark_line_amount', and the time it takes to draw 1 frame

		// NOTE: this benchmark could be some deterministic fractal pattern, which would make it look a lot cooler.
		actualToWantedRatio := benchmark_fps_tracker.last_fps / 60
		line_benchmark_line_amount = max(
			1,
			int(math.ceil(actualToWantedRatio * f64(line_benchmark_line_amount))),
		)

		af.debug_log(
			"FPS: %v with line_benchmark_line_amount %v",
			benchmark_fps_tracker.last_fps,
			line_benchmark_line_amount,
		)
		af.debug_log("verts uploaded: %d, indices uploaded: %d", verts_uploaded, indices_uploaded)
	}

	af.set_draw_color(af.Color{1, 0, 0, 0.1})
	draw_random_lines(line_benchmark_line_amount, line_benchmark_thickness)
}

draw_random_lines :: proc(count: int, thickness: f32) {
	for i in 0 ..< count {
		x1 := af.vw() * randf()
		y1 := af.vh() * randf()

		x2 := af.vw() * randf()
		y2 := af.vh() * randf()

		af.draw_line(af.im, {x1, y1}, {x2, y2}, thickness, .Circle)
	}
}


fb: ^af.Framebuffer
monospace_font: ^af.DrawableFont
wCX :: 400
wCY :: 300

draw_framebuffer_test :: proc() {
	draw_dual_circles_center :: proc(x, y: f32) {
		af.draw_circle(af.im, {x - 100, y - 100}, 200, 64)
		af.draw_circle(af.im, {x + 100, y + 100}, 200, 64)
	}

	layout_rect := af.layout_rect
	af.set_framebuffer(fb)
	{
		af.set_layout_rect(af.framebuffer_rect, false)
		af.clear_screen(af.Color{0, 0, 0, 0})
		af.set_camera_2D(0, 0, 1, 1)

		af.draw_rect(af.im, af.Rect{0, 0, 800, 600})

		transform := linalg.matrix4_translate(af.Vec3{0, 0, 0})
		af.set_transform(transform)

		af.set_draw_color(af.Color{0, 0, 1, 1})
		draw_dual_circles_center(wCX, wCY)

		af.set_draw_color(af.Color{1, 1, 0, 1})
		af.draw_rect(af.im, af.Rect{wCX, wCY, 50, 50})
	}
	af.set_framebuffer(nil)
	af.set_layout_rect(layout_rect, false)

	af.set_camera_2D(0, 0, 1, 1)

	af.set_draw_color(af.Color{1, 0, 0, 1})
	rectSize :: 200
	af.draw_rect(af.im, af.Rect{wCX - rectSize, wCY - rectSize, 2 * rectSize, 2 * rectSize})

	af.set_draw_texture(fb.texture)
	af.set_draw_color(af.Color{1, 1, 1, 0.5})
	af.draw_rect(af.im, af.Rect{0, 0, 800, 600})

	af.set_draw_texture(nil)

	af.set_draw_color(af.Color{0, 1, 0, 0.5})
	af.draw_rect_outline(af.im, af.Rect{0, 0, 800, 600}, 10)
}


draw_geometry_and_outlines_test :: proc() {
	ArcTestCase :: struct {
		x, y, r, a1, a2: f32,
		edge_count:      int,
		thickness:       f32,
	}

	arc_test_cases :: []ArcTestCase {
		{200, 200, 50, math.PI / 2, 3 * math.PI / 2, 3, 10},
		{300, 300, 50, 0, 3 * math.PI, 2, 10},
		{400, 400, 50, -math.PI / 2, math.PI / 2, 3, 10},
	}

	for t in arc_test_cases {
		af.set_draw_color(af.Color{1, 0, 0, 0.5})
		af.draw_arc(af.im, {t.x, t.y}, t.r, t.a1, t.a2, t.edge_count)

		af.set_draw_color(af.Color{0, 0, 1, 1})
		af.draw_arc_outline(af.im, {t.x, t.y}, t.r, t.a1, t.a2, t.edge_count, t.thickness)
	}

	af.set_draw_color(af.Color{1, 0, 0, 0.5})
	af.draw_rect(af.im, af.Rect{20, 20, 80, 80})
	af.set_draw_color(af.Color{0, 0, 1, 1})
	af.draw_rect_outline(af.im, af.Rect{20, 20, 80, 80}, 5)

	af.set_draw_color(af.Color{1, 0, 0, 0.5})
	af.draw_circle(af.im, {500, 500}, 200, 64)
	af.set_draw_color(af.Color{0, 0, 1, 1})
	af.draw_circle_outline(af.im, {500, 500}, 200, 64, 10)

	lineSize :: 100

	LineTestCase :: struct {
		x0, y0, x1, y1, thickness: f32,
		cap_type:                  af.CapType,
		outline_thickness:         f32,
	}
	line_test_cases := []LineTestCase {
		{af.vw() - 60, 60, af.vw() - 100, af.vh() - 100, 10.0, .None, 10},
		{af.vw() - 100, 60, af.vw() - 130, af.vh() - 200, 10.0, .Circle, 10},
		{lineSize, lineSize, af.vw() - lineSize, af.vh() - lineSize, lineSize / 2, .Circle, 10},
	}

	for t in line_test_cases {
		af.set_draw_color(af.Color{1, 0, 0, 0.5})
		af.draw_line(af.im, {t.x0, t.y0}, {t.x1, t.y1}, t.thickness, t.cap_type)

		af.set_draw_color(af.Color{0, 0, 1, 1})
		af.draw_line_outline(
			af.im,
			{t.x0, t.y0},
			{t.x1, t.y1},
			t.thickness,
			t.cap_type,
			t.outline_thickness,
		)
	}
}

arc_test_a: f32 = 0
arc_test_b: f32 = 0


draw_arc_test :: proc() {
	af.set_draw_color(af.Color{1, 0, 0, 0.5})

	x0 := af.vw() * 0.5
	y0 := af.vh() * 0.5
	r := af.vw() < af.vh() ? af.vw() : af.vh() * 0.45

	edges :: 64 // GetEdgeCount(r, fabsf(arc_test_b - arc_test_a), 512);
	af.draw_arc(af.im, {x0, y0}, r, arc_test_a, arc_test_b, edges)

	draw_hand :: proc(x0, y0, r, angle: f32) {
		af.draw_line(
			af.im,
			{x0, y0},
			{x0 + r * math.cos(angle), y0 + r * math.sin(angle)},
			15,
			.Circle,
		)
	}

	af.set_draw_color(af.Color{0, 0, 0, 0.5})
	draw_hand(x0, y0, r, arc_test_a)
	draw_hand(x0, y0, r, arc_test_b)

	af.set_draw_color(af.Color{0, 0, 0, 1})
	// _font.DrawText(ctx, $"Angle a: {a}\nAngle b: {b}" + a, 16, new DrawTextOptions {
	//     X = 0, Y = ctx.height(), VAlign=1
	// });

	arc_test_a += f32(af.delta_time)
	arc_test_b += f32(af.delta_time) * 2.0
}


last_mouse_pos: af.Vec2
update_keyboard_and_input_test :: proc() {
	pos := af.get_mouse_pos()
	if (last_mouse_pos.x != pos.x || last_mouse_pos.y != pos.y) {
		last_mouse_pos = pos
		af.debug_log("The mouse just moved: %f, %f", pos.x, pos.y)
	}

	// TODO: convert to actual rendering once we implement text rendering. for now, we're just printf-ing everything
	for key in af.KeyCode {
		if af.key_just_pressed(key) {
			af.debug_log("Just pressed a key: %v", key)
		}

		if af.key_just_released(key) {
			af.debug_log("Just released a key: %v", key)
		}
	}
}

test_texture: ^af.Texture
test_texture_2: ^af.Texture

t: f64

draw_texture_test :: proc() {
	t += f64(af.delta_time)

	af.set_draw_color(af.Color{1, 1, 1, 0.5})

	left_rect := af.Rect{20, 20, af.vw() / 2 - 40, af.vh() - 40}
	af.set_draw_texture(test_texture)
	af.draw_rect(af.im, left_rect)

	right_rect := left_rect
	right_rect.x0 = af.vw() / 2 + 20
	af.set_draw_texture(test_texture_2)
	af.draw_rect(af.im, right_rect)
}

draw_stencil_test :: proc() {
	t += f64(af.delta_time)

	af.clear_stencil()

	af.set_draw_texture(nil)
	af.set_draw_color(af.Color{0, 0, 0, 0})

	af.set_stencil_mode(.WriteOnes)

	stencil_rect_initial := af.Rect{0, 0, af.vw(), af.vh()}
	stencil_rect := stencil_rect_initial
	af.set_rect_size(&stencil_rect, stencil_rect.width / 2, stencil_rect.height / 2, 0.5, 0.5)
	af.draw_rect(af.im, stencil_rect)

	af.set_stencil_mode(.WriteZeroes)
	af.set_rect_size(&stencil_rect, stencil_rect.width / 2, stencil_rect.height / 2, 0.5, 0.5)
	af.draw_rect(af.im, stencil_rect)

	af.set_stencil_mode(.DrawOverOnes)

	draw_texture_test()

	af.set_stencil_mode(.DrawOverZeroes)

	af.set_draw_color(af.Color{1, 0, 0, 0.5})
	af.set_draw_texture(nil)
	af.draw_rect(af.im, stencil_rect_initial)

	af.set_stencil_mode(.Off)
}

camera_mode := 0
camera_z_input: f32 = -5
camera_x_input: f32 = 0
update_camera_test :: proc() {
	if af.key_just_pressed(.Space) {
		camera_mode = (camera_mode + 1) % 2
	}

	speed :: 5

	switch {
	case af.key_is_down(.A):
		camera_x_input -= af.delta_time_update * speed
	case af.key_is_down(.D):
		camera_x_input += af.delta_time_update * speed
	}

	switch {
	case af.key_is_down(.S):
		camera_z_input -= af.delta_time_update * speed
	case af.key_is_down(.W):
		camera_z_input += af.delta_time_update * speed
	}
}

draw_camera_test :: proc() {
	// set up camera
	projection: af.Mat4
	if camera_mode == 0 {
		projection = af.get_perspective(90 * af.DEG2RAD, 0.1, 50)
	} else {
		projection = af.get_orthographic(camera_z_input, 0.1, 50)
	}

	af.set_camera_3D(
		af.Vec3{camera_x_input, 0, camera_z_input},
		af.Vec3{0, 0, 0},
		af.Vec3{0, 1, 0},
		projection,
	)
	af.set_transform(af.MAT4_IDENTITY)

	// draw an object. for now, it is just a triangle
	af.set_draw_texture(nil)
	af.set_draw_color(af.Color{1, 0, 0, 1})
	size: f32 = 5
	af.draw_triangle(
		af.im,
		af.vertex_2D({-size, -size}),
		af.vertex_2D({size, -size}),
		af.vertex_2D({0, size}),
	)
	// af.draw_circle_outline(af.im, 0, 0, 1, 64, 0.1)

	// crosshairs at the center for reference

	// crosshairs
	af.clear_depth_buffer()
	af.set_draw_texture(nil)
	af.set_draw_color(af.Color{0, 0, 0, 1})
	af.set_camera_2D(af.vw() / 2, af.vh() / 2, 1, 1)
	size = 50
	width: f32 = 1
	crosshair := af.Rect{-size, -width, 2 * size, width * 2}
	crosshair2 := af.Rect{-width, -size, width * 2, 2 * size}
	af.draw_rect(af.im, crosshair)
	af.draw_rect(af.im, crosshair2)

	af.draw_font_text(
		af.im,
		monospace_font,
		fmt.tprintf("%v, %v", camera_x_input, camera_z_input),
		32,
		{-af.vw() / 2 + 10, 0},
	)

}

nothing_proc :: proc() {}

text_test_text_worldwide_1 :: "!#$%&\"()*+,-./ 😎😎😎 💯 0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~'昨夜のコンサートは最高でした уилщертхуилоыхнлойк MR Worldwide 😎😎😎 💯 💯 💯 "
draw_text_test :: proc() {
	t += f64(af.delta_time)

	size :: 32
	// text := "| _"
	// text := "ab.gjH;$%"
	text: string = text_test_text_worldwide_1

	af.set_draw_color(af.Color{0, 0, 0, 1})
	res := af.draw_font_text(af.im, monospace_font, text, size, {0, 0}, is_measuring = true)
	x: f32 = af.vw() / 2 - res.width / 2 + res.width * 0.5 * math.sin_f32(f32(t * 0.25))
	y: f32 = size * 2
	af.draw_font_text(af.im, monospace_font, text, size, {x, y})

	af.set_draw_color(af.Color{1, 0, 0, 0.1})
	af.set_draw_texture(nil)
	af.draw_rect(af.im, af.Rect{0, 0, af.vw(), af.vh()})

	// draw the atlas as well
	af.set_draw_color(af.Color{1, 0, 0, 1})
	af.set_draw_texture(monospace_font.texture)
	af.draw_rect_uv(af.im, af.Rect{0, 0, af.vw(), af.vh()}, af.Rect{0, 0, 0.25, 0.25})
	af.draw_rect(af.im, af.Rect{0, 0, af.vw(), af.vh()})

	af.set_draw_texture(nil)
}


Testcase :: struct {
	render_fn: proc(),
	update_fn: proc(),
	name:      string,
	doc:       string,
}
current_rendering_test := 0
rendering_tests := [](Testcase) {
	Testcase {
		draw_text_test,
		nothing_proc,
		"",
		`Does basic text rendering work? Does not test the edge-cases yet`,
	},
	Testcase {
		draw_benchmark_test,
		nothing_proc,
		"draw_benchmark_test",
		`A test that measures how fast the immediate mode is`,
	},
	Testcase {
		draw_framebuffer_test,
		nothing_proc,
		"draw_framebuffer_test",
		`Do framebuffers work?`,
	},
	Testcase {
		draw_geometry_and_outlines_test,
		nothing_proc,
		"draw_geometry_and_outlines_test",
		`Do the geometry and outline drawing methods work?`,
	},
	Testcase{draw_arc_test, nothing_proc, "draw_arc_test", `Do arcs draw as expected?`},
	Testcase {
		nothing_proc,
		update_keyboard_and_input_test,
		"update_keyboard_and_input_test",
		`Does keyboard input work?`,
	},
	Testcase{draw_texture_test, nothing_proc, "draw_texture_test", `Does texture loading work?`},
	Testcase {
		draw_stencil_test,
		nothing_proc,
		"draw_stencil_test",
		`Do the stencilling methods work?`,
	},
	Testcase {
		draw_camera_test,
		update_camera_test,
		"draw_camera_test",
		`Are the projection matrices which are relative to the current layour rect working as expected? (The center of the red triangle must be exactly over the crosshairs when the mouse is over the crosshairs)`,
	},
}

update_rendering_tests :: proc() -> bool {
	if af.key_just_pressed(af.KeyCode.Escape) {
		return false
	}
	changed_test := true
	// NOTE: current_rendering_test must never be set to an out-of-bounds value, because it is being read on a separate thread
	switch {
	case af.key_just_pressed(af.KeyCode.Right):
		if current_rendering_test + 1 >= len(rendering_tests) {
			current_rendering_test = 0
		} else {
			current_rendering_test += 1
		}
	case af.key_just_pressed(af.KeyCode.Left):
		if current_rendering_test - 1 < 0 {
			current_rendering_test = len(rendering_tests) - 1
		} else {
			current_rendering_test -= 1
		}
	case:
		changed_test = false
	}
	tt := rendering_tests[current_rendering_test]
	if changed_test {
		af.debug_log("\nTest [%d] - %s", current_rendering_test, tt.name)
	}

	tt.update_fn()

	return true
}

draw_rendering_tests :: proc() {
	tt := rendering_tests[current_rendering_test]

	af.clear_screen(af.Color{1, 1, 1, 1})

	// draw label
	af.set_draw_color({0, 0, 0, 1})
	af.set_draw_texture(nil)
	text_size :: 32
	af.draw_font_text(af.im, monospace_font, tt.name, text_size, {10, af.vh() - text_size - 10})

	// test region 
	test_region := af.layout_rect
	af.set_rect_width(&test_region, af.vw() * 0.6, 0.7)
	af.set_rect_height(&test_region, af.vh() * 0.6, 0.7)
	af.set_layout_rect(test_region, clip = true)

	// draw the test
	af.set_camera_2D(0, 0, 1, 1)
	tt.render_fn()

	// red outline
	af.set_layout_rect(test_region, false)
	af.clear_depth_buffer()
	af.set_draw_color(af.Color{1, 0, 0, 0.5})
	af.set_draw_texture(nil)
	r := af.Rect{0, 0, af.vw(), af.vh()}
	af.draw_rect_outline(af.im, r, 5)

	verts_uploaded, indices_uploaded = af.vertices_uploaded, af.indices_uploaded

	render_diagnostics()
}

render_diagnostics :: proc() {
	af.set_layout_rect(af.window_rect, false)
	af.set_draw_params({0, 0, 0, 1})
	af.draw_font_text(
		af.im,
		monospace_font,
		fmt.tprintf(
			"r:%.0fhz,%.2f,%d|u%.0fhz,%.2f,%d",
			af.fps_tracker_render.last_fps,
			af.fps_tracker_render.timer,
			af.fps_tracker_render.frames,
			af.fps_tracker_update.last_fps,
			af.fps_tracker_update.timer,
			af.fps_tracker_update.frames,
		),
		32,
		{10, 10},
	)
}

// I sometimes have to use this to check if there are problems with the immmediate mode rendering
get_diagnostic_mesh :: proc() -> ^af.Mesh {
	mesh := af.new_mesh(4, 6)

	mesh.indices[0] = 0
	mesh.indices[1] = 1
	mesh.indices[2] = 2
	mesh.indices[3] = 2
	mesh.indices[4] = 3
	mesh.indices[5] = 0

	mesh.vertices[0] = af.vertex_2D({-50, -50})
	mesh.vertices[1] = af.vertex_2D({-50, 50})
	mesh.vertices[2] = af.vertex_2D({50, 50})
	mesh.vertices[3] = af.vertex_2D({50, -50})

	af.upload_mesh(mesh, false)

	return mesh
}

fb_texture: ^af.Texture
test_image: ^af.Image

init_tests :: proc() {
	af.set_window_title("Testing the thing")
	af.maximize_window()
	af.show_window()

	// init test resources
	fb_texture = af.new_texture_from_size(1, 1)
	fb = af.new_framebuffer(fb_texture)
	af.resize_framebuffer(fb, 800, 600)

	test_image = af.new_image("./res/settings_icon.png")

	texture_settings := af.DEFAULT_TEXTURE_CONFIG

	texture_settings.filtering = af.TEXTURE_FILTERING_LINEAR
	test_texture = af.new_texture_from_image(test_image, texture_settings)

	texture_settings.filtering = af.TEXTURE_FILTERING_NEAREST
	test_texture_2 = af.new_texture_from_image(test_image, texture_settings)

	// texture_grid_size=4 for test purposes to test the font cache evicting
	monospace_font = af.new_font("./res/SourceCodePro-Regular.ttf", 32, texture_grid_size = 4)
	// mesh := GetDiagnosticMevh()
}

uninit_tests :: proc() {
	defer af.un_initialize()

	defer af.free_texture(fb_texture)
	defer af.free_framebuffer(fb)
	defer af.free_image(test_image)
	defer af.free_texture(test_texture)
	defer af.free_texture(test_texture_2)
	defer af.free_font(monospace_font)
}


run_all_tests_singlethreaded :: proc() {
	for af.new_update_frame() {
		update_rendering_tests()

		af.begin_render_frame()
		draw_rendering_tests()
		af.end_render_frame()
	}
}

/*

TODO: 
- [x] get multithreaded working
- [x] get sleep_for_hz working
- [x] update at 2000hz
- [x] Fix black screen flicker wile resizing
- [] render at monitor's refresh rate, 
- [x] convert the tests to render+update pairs

*/

run_all_tests_multithreaded :: proc() {
	af.set_vsync(true)
	// af.set_target_render_fps(60)

	render_thread_proc :: proc() {
		draw_rendering_tests()
	}
	rt := af.start_render_thread(render_thread_proc)

	af.target_fps_update = 240

	for af.new_update_frame() {
		if !update_rendering_tests() {
			break
		}
	}

	af.stop_and_join_render_thread(rt)
}

main :: proc() {
	if (!af.initialize(800, 600)) {
		af.debug_log("Could not initialize. rip\n")
		return
	}

	init_tests()
	defer uninit_tests()

	// run_all_tests_singlethreaded()
	run_all_tests_multithreaded()
}
