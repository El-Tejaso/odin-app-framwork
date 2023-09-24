
package main

import "af"
import "core:fmt"

import "core:math"
import "core:math/linalg"
import "core:math/rand"

/**

Not everything has been ported just yet

TODO:

- [] Stencil test
- [] Texture test
- [] Perspective camera test
- [x] Keyboard input test
- [] Text rendering 
	- [] code
		- [] utf-8 parsing
		- [] Freetype signed distance fields
	- [] tests/examples
- [] New audio engine
	- [] code
	- [] tests/examples
*/

randf :: proc() -> f32 {
	return rand.float32()
}

t: f64 = 0
fps, current_frames: int

// returns true if we ticked up
TrackFps :: proc(interval: f64) -> bool {
	t += af.delta_time
	if (t > interval) {
		t = 0
		fps = int(f64(current_frames) / interval)
		current_frames = 0
		return true
	}

	current_frames += 1
	return false
}

line_benchmark_line_amount := 200
line_benchmark_thickness :: 5

DrawBenchmarkTest :: proc() {
	rand.set_global_seed(0)

	if (TrackFps(1.0)) {
		// try to figure out how many lines we need to draw to get 60 fps.
		// we are assuming there is a linear relationship between 'line_benchmark_line_amount', and the time it takes to draw 1 frame

		// NOTE: this benchmark could be some deterministic fractal pattern, which would make it look a lot cooler.
		actualToWantedRatio := f64(fps) / 60
		line_benchmark_line_amount = int(
			math.ceil(actualToWantedRatio * f64(line_benchmark_line_amount)),
		)

		fmt.printf("FPS: %v with line_benchmark_line_amount %v\n", fps, line_benchmark_line_amount)
	}

	af.SetDrawColor(af.Color{1, 0, 0, 0.1})

	for i in 0 ..< line_benchmark_line_amount {
		x1 := af.VW() * randf()
		y1 := af.VH() * randf()

		x2 := af.VW() * randf()
		y2 := af.VH() * randf()

		af.DrawLine(af.mb_im, x1, y1, x2, y2, line_benchmark_thickness, .Circle)
	}
}


fb: ^af.Framebuffer
wCX :: 400
wCY :: 300

FramabufferTest__DrawDualCirclesCenter :: proc(x, y: f32) {
	af.DrawCircle(af.mb_im, x - 100, y - 100, 200, 64)
	af.DrawCircle(af.mb_im, x + 100, y + 100, 200, 64)
}

DrawFramebufferTest :: proc() {
	af.UseFramebuffer(fb)
	{
		af.ClearScreen(af.Color{0, 0, 0, 0})
		af.SetViewProjection_Cartesian2D(0, 0, 1, 1)

		af.DrawRect(af.mb_im, af.Rect{0, 0, 800, 600})

		transform := linalg.matrix4_translate(af.Vec3{0, 0, 0})
		af.SetTransform(transform)

		af.SetDrawColor(af.Color{0, 0, 1, 1})
		FramabufferTest__DrawDualCirclesCenter(wCX, wCY)

		af.SetDrawColor(af.Color{1, 1, 0, 1})
		af.DrawRect(af.mb_im, af.Rect{wCX, wCY, 50, 50})
	}
	af.UseFramebuffer(nil)

	af.SetViewProjection_Cartesian2D(0, 0, 1, 1)

	af.SetDrawColor(af.Color{1, 0, 0, 1})
	rectSize :: 200
	af.DrawRect(af.mb_im, af.Rect{wCX - rectSize, wCY - rectSize, 2 * rectSize, 2 * rectSize})

	af.SetTexture(fb.texture)
	af.SetDrawColor(af.Color{1, 1, 1, 0.5})
	af.DrawRect(af.mb_im, af.Rect{0, 0, 800, 600})

	af.SetTexture(nil)

	af.SetDrawColor(af.Color{0, 1, 0, 0.5})
	af.DrawRectOutline(af.mb_im, af.Rect{0, 0, 800, 600}, 10)
}


DrawGeometryAndOutlinesTest :: proc() {
	ArcTestCase :: struct {
		x, y, r, a1, a2: f32, edge_count: int, thickness : f32
	}

	arc_test_cases :: []ArcTestCase{
		{200, 200, 50, math.PI / 2, 3 * math.PI / 2, 3, 10},
		{300, 300, 50, 0, 3 * math.PI, 2, 10},
		{400, 400, 50, -math.PI / 2, math.PI / 2, 3, 10},
	}

	for t in arc_test_cases {
		af.SetDrawColor(af.Color{1, 0, 0, 0.5})
		af.DrawArc(af.mb_im, t.x, t.y, t.r, t.a1, t.a2, t.edge_count)
		
		af.SetDrawColor(af.Color{0, 0, 1, 1})
		af.DrawArcOutline(af.mb_im, t.x, t.y, t.r, t.a1, t.a2, t.edge_count, t.thickness)
	}
	
	af.SetDrawColor(af.Color{1, 0, 0, 0.5})
	af.DrawRect(af.mb_im, af.Rect{20, 20, 80, 80})
	af.SetDrawColor(af.Color{0, 0, 1, 1})
	af.DrawRectOutline(af.mb_im, af.Rect{20, 20, 80, 80}, 5)
	
	af.SetDrawColor(af.Color{1, 0, 0, 0.5})
	af.DrawCircle(af.mb_im, 500, 500, 200, 64)
	af.SetDrawColor(af.Color{0, 0, 1, 1})
	af.DrawCircleOutline(af.mb_im, 500, 500, 200, 64, 10)

	lineSize :: 100

	LineTestCase :: struct {
		x0, y0, x1, y1, thickness: f32,
		cap_type: af.CapType,
		outline_thickness: f32
	}
	line_test_cases := []LineTestCase {
		{af.VW() - 60, 60, af.VW() - 100, af.VH() - 100, 10.0, .None, 10},
		{af.VW() - 100, 60, af.VW() - 130, af.VH() - 200, 10.0, .Circle, 10},
		{lineSize, lineSize, af.VW() - lineSize, af.VH() - lineSize, lineSize / 2, .Circle, 10},
	}

	for t in line_test_cases {
		af.SetDrawColor(af.Color{1, 0, 0, 0.5})
		af.DrawLine(af.mb_im, t.x0, t.y0, t.x1, t.y1, t.thickness, t.cap_type)
		
		af.SetDrawColor(af.Color{0, 0, 1, 1})
		af.DrawLineOutline(af.mb_im, t.x0, t.y0, t.x1, t.y1, t.thickness, t.cap_type, t.outline_thickness)
	}
}

arc_test_a: f32 = 0
arc_test_b: f32 = 0

DrawArcTest__DrawHand :: proc(x0, y0, r, angle: f32) {
	af.DrawLine(af.mb_im, x0, y0, x0 + r * math.cos(angle), y0 + r * math.sin(angle), 15, .Circle)
}

DrawArcTest :: proc() {
	af.SetDrawColor(af.Color{1, 0, 0, 0.5})

	x0 := af.VW() * 0.5
	y0 := af.VH() * 0.5
	r := af.VW() < af.VH() ? af.VW() : af.VH() * 0.45

	edges :: 64 // GetEdgeCount(r, fabsf(arc_test_b - arc_test_a), 512);
	af.DrawArc(af.mb_im, x0, y0, r, arc_test_a, arc_test_b, edges)

	af.SetDrawColor(af.Color{0, 0, 0, 0.5})
	DrawArcTest__DrawHand(x0, y0, r, arc_test_a)
	DrawArcTest__DrawHand(x0, y0, r, arc_test_b)

	af.SetDrawColor(af.Color{0, 0, 0, 1})
	// _font.DrawText(ctx, $"Angle a: {a}\nAngle b: {b}" + a, 16, new DrawTextOptions {
	//     X = 0, Y = ctx.VH, VAlign=1
	// });

	arc_test_a += f32(af.delta_time)
	arc_test_b += f32(af.delta_time) * 2.0
}


last_mouse_pos: af.Vec2
DrawKeyboardAndInputTest :: proc() {
	pos := af.GetMousePos()
	if (last_mouse_pos.x != pos.x || last_mouse_pos.y != pos.y) {
		last_mouse_pos = pos
		fmt.printf("The mouse just moved: %f, %f\n", pos.x, pos.y)
	}

	// TODO: convert to actual rendering once we implement text rendering. for now, we're just printf-ing everything
	for key in af.KeyCode {
		if af.KeyJustPressed(key) {
			fmt.printf("Just pressed a key: %v\n", key)
		}

		if af.KeyJustReleased(key) {
			fmt.printf("Just released a key: %v\n", key)
		}
	}
}

DrawRenderingTests :: proc() {
	test_region := af.layout_rect
	af.Rect_SetWidth(&test_region, af.VW() * 0.75, 0.6)
	af.Rect_SetHeight(&test_region, af.VH() * 0.75, 0.6)
	af.SetLayoutRect(test_region, false)

	af.SetDrawColor(af.Color{1, 0, 0, 0.5})
	r := af.Rect{0, 0, af.VW(), af.VH()}
	af.DrawRectOutline(af.mb_im, r, 5)

	af.SetLayoutRect(test_region, false)
	DrawBenchmarkTest()

	af.SetLayoutRect(test_region, false)
	DrawFramebufferTest()

	af.SetLayoutRect(test_region, false)
	DrawArcTest()

	af.SetLayoutRect(test_region, false)
	DrawGeometryAndOutlinesTest()

	af.SetLayoutRect(test_region, false)
	DrawKeyboardAndInputTest()
}

// I sometimes have to use this to check if there are problems with the immmediate mode rendering
GetDiagnosticMesh :: proc() -> ^af.Mesh {
	mesh := af.Mesh_Make(4, 6)
	mesh.indices[0] = 0
	mesh.indices[1] = 1
	mesh.indices[2] = 2
	mesh.indices[3] = 2
	mesh.indices[4] = 3
	mesh.indices[5] = 0

	mesh.vertices[0] = af.GetVertex2D(-50, -50)
	mesh.vertices[1] = af.GetVertex2D(-50, 50)
	mesh.vertices[2] = af.GetVertex2D(50, 50)
	mesh.vertices[3] = af.GetVertex2D(50, -50)
	
	af.Mesh_Upload(mesh, false)

	return mesh
}

main :: proc() {
	if (!af.Init(800, 600, "Testing the thing")) {
		fmt.printf("Could not initialize. rip\n")
        return
	}
    
	// init test resources
	fb = af.Framebuffer_MakeFromTexture(af.Texture_FromSize(1, 1))
	defer af.Framebuffer_Free(fb)
	af.Framebuffer_Resize(fb, 800, 600)

	// mesh := GetDiagnosticMesh()

	for !af.WindowShouldClose() && !af.KeyJustPressed(af.KeyCode.Escape) {
		af.BeginFrame()

		af.ClearScreen(af.Color{1, 1, 1, 1})

		// af.SetTransform(af.MAT4_IDENTITY)
		// af.SetView(af.MAT4_IDENTITY)
		// af.SetProjection(af.MAT4_IDENTITY)
		// af.SetViewProjection_Cartesian2D(0, 0, 1, 1)
		// af.SetDrawColor(af.Color{1, 0, 0, 1})
		// af.Mesh_Draw(mesh, 6)
		// af.DrawQuad(
		// 	af.mb_im,
		// 	mesh.vertices[0], 
		// 	mesh.vertices[1], 
		// 	mesh.vertices[2], 
		// 	mesh.vertices[3], 
		// );

		DrawRenderingTests()

		af.EndFrame()
	}

	af.UnInit()
}
