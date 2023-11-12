package rect

Rect :: struct($T: typeid) {
	l, r, t, b: T,
}

RectF :: Rect(f32)
RectI :: Rect(int)

RECTF_LERP_INIT :: RectF { -1, -1, -1, -1 }

RECTF_INF :: RectF { max(f32), -max(f32), max(f32), -max(f32) }
RECTI_INF :: RectI { max(int), -max(int), max(int), -max(int) }

// convert a integer to float rect
i2f :: proc(rect: RectI) -> RectF {
	return { f32(rect.l), f32(rect.r), f32(rect.t), f32(rect.b) }
}

// convert a float to integer rect
f2i :: proc(rect: RectF) -> RectI {
	return { int(rect.l), int(rect.r), int(rect.t), int(rect.b) }
}

// return a rect initialized with x/y & w/h
wh :: proc(x, y, w, h: $T) -> (res: Rect(T)) {
	res.l = x
	res.r = x + w
	res.t = y
	res.b = y + h
	return
}

// return a rect thats initialized from input, x1/x2 while remaining height
hori :: proc(input: Rect($T) x1, x2, pad: T) -> (res: Rect(T)) {
	res = input
	res.l = x1 - pad
	res.r = x2 + pad
	return
}

// modify the rect to be set by pos and size
sized :: proc(pos: [2]$T, size: [2]T) -> (res: Rect(T)) {
	res.l = pos.x
	res.r = pos.x + size.x
	res.t = pos.y
	res.b = pos.y + size.y
	return
}

// return wether "a" and "b" overlap each other
overlap :: proc(a, b: Rect($T)) -> bool {
	return b.r >= a.l && b.l <= a.r && b.b >= a.t && b.t <= a.b
}

// push x/y to a rectangle - stacking up bounds
// init the rect with RECT_INF to start out
inf_push :: proc(rect: ^Rect($T), x: T, y: T) {
	rect.l = min(rect.l, x)
	rect.r = max(rect.r, x)
	rect.t = min(rect.t, y)
	rect.b = max(rect.b, y)
}

// returns the center point x/y of the rectangle
center :: proc(rect: RectF) -> (f32, f32) {
	return rect.l + (rect.r - rect.l) / 2, rect.t + (rect.b - rect.t) / 2
}

centerx :: proc(rect: RectF) -> f32 {
	return rect.l + (rect.r - rect.l) / 2
}

centery :: proc(rect: RectF) -> f32 {
	return rect.t + (rect.b - rect.t) / 2
}

// returns true if width/height is above 0
valid :: proc(rect: Rect($T)) -> bool {
	return (rect.r - rect.l) > 0 && (rect.b - rect.t) > 0
}

// returns true if width/height is below 0
invalid :: #force_inline proc(rect: Rect($T)) -> bool { return !valid(rect) }

// returns the result of the intersection of "a" and "b"
intersection :: proc(a, b: Rect($T)) -> (res: Rect(T)) {
  res = a
  if a.l < b.l do res.l = b.l
  if a.t < b.t do res.t = b.t
  if a.r > b.r do res.r = b.r
  if a.b > b.b do res.b = b.b
  return
}

// return the rect applied with a margin "value"
margin :: proc(a: Rect($T), value: T) -> Rect(T) {
	a := a
	a.l += value
	a.t += value
	a.r -= value
	a.b -= value
	return a
}

// offset a rect by x/y
offset :: proc(rect: Rect($T), x, y: T) -> (res: Rect(T)) {
	res = rect
	res.l += x
	res.r += x
	res.t += y
	res.b += y
	return
}

// offset a rect by x
offsetx :: proc(rect: Rect($T), x: T) -> (res: Rect(T)) {
	res = rect
	res.l += x
	res.r += x
	return
}

// offset a rect by y
offsety :: proc(rect: Rect($T), y: T) -> (res: Rect(T)) {
	res = rect
	res.t += y
	res.b += y
	return
}

// true if x/y is contained within the rect
contains :: proc(a: Rect($T), x, y: T) -> bool {
	return a.l <= x && a.r > x && a.t <= y && a.b > y
}

// width in float
width :: proc "contextless" (a: RectF) -> f32 {
	return a.r - a.l
}

// height in float
height :: proc "contextless" (a: RectF) -> f32 {
	return a.b - a.t
}

// width in float
widthf :: proc "contextless" (a: RectI) -> f32 {
	return f32(a.r - a.l)
}

// height in float
heightf :: proc "contextless" (a: RectI) -> f32 {
	return f32(a.b - a.t)
}

// width in int
widthi :: proc "contextless" (a: RectI) -> int {
	return a.r - a.l
}

// height in int
heighti :: proc "contextless" (a: RectI) -> int {
	return a.b - a.t
}

// split into 4 pieces separated by w/h unit
split_quad :: proc(a: RectF, wunit := f32(0.5), hunit := f32(0.5)) -> (res: [4]RectF) {
	w2 := (a.r - a.l) * wunit
	h2 := (a.b - a.t) * hunit

	res[0] = { a.l, a.l + w2, a.t, a.t + h2 } // TL
	res[1] = { a.l + w2, a.r, a.t, a.t + h2 } // TR
	res[2] = { a.l, a.l + w2, a.t + h2, a.b } // BL
	res[3] = { a.l + w2, a.r, a.t + h2, a.b } // BR

	return
}

// split vertical
split_vertical :: proc(rect: RectF) -> (left, right: RectF) {
	left = rect
	right = rect
	left.r = rect.l + (rect.r - rect.l) / 2
	right.l = left.r
	return
}

// split a rectangle into for parts that may all be open or only a single one
split_kanban :: proc(a: RectF, open: [4]f32) -> (res: [4]RectF) {
	total := open[0] * open[1] * open[2] * open[3]
	assert(total > 0)
	units: [4]f32
	w := width(a)

	x := a.l
	for i in 0..<4 {
		next := x + w * open[i] / total
		res[i] = { x, next, a.t, a.b }
		x = next
	}

	return
}

// cut "a" amount of rect and return the cut result
cut_left :: proc(rect: ^Rect($T), a: T) -> (res: Rect(T)) {
	res = rect^
	res.r = rect.l + a
	rect.l = res.r
	return
}

// cut "a" amount of rect and return the cut result
cut_right :: proc(rect: ^Rect($T), a: T) -> (res: Rect(T)) {
	res = rect^
	res.l = rect.r - a
	rect.r = res.l
	return
}

// cut "a" amount of rect and return the cut result
cut_top :: proc(rect: ^Rect($T), a: T) -> (res: Rect(T)) {
	res = rect^
	res.b = rect.t + a
	rect.t = res.b
	return
}

// cut "a" amount of rect and return the cut result
cut_bottom :: proc(rect: ^Rect($T), a: T) -> (res: Rect(T)) {
	res = rect^
	res.t = rect.b - a
	rect.b = res.t
	return
}

// clamp a rectangle to stay within another rect
clamp_within :: proc(clamping: ^RectF, within: RectF) {
	width := clamping.r - clamping.l
	height := clamping.b - clamping.t
	clamping.l = clamp(clamping.l, within.l, within.r - width)
	clamping.r = clamp(clamping.r, within.l + width, within.r)
	clamping.t = clamp(clamping.t, within.t, within.b - height)
	clamping.b = clamp(clamping.b, within.t + height, within.b)
}

flat :: proc(a: RectF) -> [4]f32 {
	return { a.l, a.r, a.t, a.b }
}
