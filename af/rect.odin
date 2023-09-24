package af

Rect :: struct {
	x0, y0, width, height: f32,
}

Rect_SetWidth :: proc(rect: ^Rect, new_width, pivot: f32) {
	delta := new_width - rect.width
	rect.x0 -= delta * pivot
	rect.width = new_width
}

Rect_SetHeight :: proc(rect: ^Rect, new_height, pivot: f32) {
	delta := new_height - rect.height
	rect.y0 -= delta * pivot
	rect.height = new_height
}

Rect_Rectify :: proc(rect: ^Rect) {
	if rect.height < 0 {
		rect.y0 += rect.height
		rect.height = -rect.height
	}

	if rect.width < 0 {
		rect.x0 += rect.width
		rect.width = -rect.width
	}
}

Rect_Intersect :: proc(r1, r2: ^Rect) -> Rect {
	rix0 := max(r1.x0, r2.x0)
	rix1 := min(r1.x0 + r1.width, r2.x0 + r2.width)
	riwidth := rix1 - rix0
	
	riy0 := max(r1.y0, r2.y0)
	riy1 := min(r1.y0 + r1.width, r2.y0 + r2.width)
	riheight := riy1 - riy0

	return Rect {rix0, riy0, riwidth, riheight}
}
