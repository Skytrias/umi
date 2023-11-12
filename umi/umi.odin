package umi

import "core:mem"
import "core:fmt"
import "core:time"
import "core:hash"
import "core:slice"
import "core:intrinsics"
import "core:unicode/utf8"
import dll "core:container/intrusive/list"
import "../rect"

// HELPER ELEMENTS
// splitter pixels/ratio + reset
// dialog (+ result)
// tooltips
// text box
// toolbar (collection)

// tooltip
//    position based on item side
//    multiple at once with fades	

CALL_NONE :: -1
CALL_SOME :: 1
MAX_DATASIZE :: 4096
MAX_DEPTH :: 64
MAX_INPUT_EVENTS :: 64
MAX_BUCKETS :: 256
CLICK_THRESHOLD :: time.Millisecond * 250
MAX_CONSUME :: 256
SCROLLBAR_CAP :: 256
TOGGLE_CAP :: 256

RectI :: rect.RectI
RectF :: rect.RectF
I2 :: [2]int
V2 :: [2]f32

Id :: u32

Cursor_Handle_Callback :: #type proc(ctx: ^Context, cursor: int)

Input_Event :: struct {
	key: string,
	char: rune,
	call: Call,
}

Mouse_Button :: enum {
	Left,
	Middle,
	Right,
}
Mouse_Buttons :: bit_set[Mouse_Button]

Context :: struct {
	// userdata
	user_ptr: rawptr,
	dt: f32,

	// mouse state
	buttons: Mouse_Buttons,
	last_buttons: Mouse_Buttons,
	button_capture: Mouse_Button,
	button_ignore: Maybe(Mouse_Button),

	// cursor
	cursor_start: I2,
	cursor_last_frame: I2,
	cursor_delta_frame: I2,
	cursor_offset: I2, // offset to item that was pressed down
	cursor: I2,
	cursor_handle: int, // handle <-> looks
	cursor_handle_callback: Cursor_Handle_Callback, // callback on handle change
	scroll: I2,

	// item ids
	active_item: Id,
	focus_item: Id,
	focus_redirect_item: Id, // redirect messages if no item is focused to this item
	last_hot_item: Id,
	last_click_item: Id,
	hot_item: Id,
	clicked_item: Id,

	// timestamp when a capture started
	capture_start: [Mouse_Button]time.Time,

	// stages
	state: State,
	stage: Stage,

	// key info
	active_key: string,
	active_char: rune,

	// consume building
	consume: [MAX_CONSUME]u8,
	consume_focused: bool, // wether consuming is active
	consume_index: int,

	// click counting
	clicks: int,
	click_time: time.Time,

	item_pool: Pool(Item),
	item_links: []dll.List, // hash links
	item_sort: []^Item, // temp array for storing sorted results before clone
	frame_index: uint,

	// short lived pointers
	arena_bytes: []byte,
	arena: mem.Arena,

	// input event buffer
	events: [MAX_INPUT_EVENTS]Input_Event,
	event_count: int,

	// tooltips
	root: ^Item,
	tooltips: ^Item, // upper level tooltips, needs to spawned next to root
}

State :: enum {
	Idle,
	Capture,
}

Stage :: enum {
	Layout,
	Post_Layout,
	Process,
}

// Cut modes
Cut :: enum {
	Left,
	Right,
	Top,
	Bottom,
	Fill,
}

// LAYOUT MODES
// 1. RectCut Layouting (directionality + cut distance)
// 2. Absolute Layouting (set the rect yourself)
// 3. Relative Layouting (set the rect yourself relative to a parent)
// 4. flex grid (pixel limits + 1-12 slots) + wrapping
Layout :: enum {
	Cut,
	Absolute,
	Relative,
	Flow,
}

// MOUSE calls:
//   Down / Up called 1 frame
//   Hot_Up called when active was over hot
//   Capture called while holding active down
Call :: enum {
	// left mouse button
	Left_Down,
	Left_Up,
	Left_Hot_Up,
	Left_Capture,

	// right mouse button
	Right_Down,
	Right_Up,
	Right_Hot_Up,
	Right_Capture,

	// middle mouse button
	Middle_Down,
	Middle_Up,
	Middle_Hot_Up,
	Middle_Capture,

	// Scroll info
	Scroll,

	// Cursor Info
	Cursor_Handle,

	// FIND
	Find_Ignore,

	// overridable width/height of an element - useful for labels or dynamic sizes
	Dynamic_Width,
	Dynamic_Height,

	// custom layout method, skips regular layouting for this item
	// parent can decide how to layout its children
	Layout_Custom,

	Update, // runs through tree before painting
	Paint_Start,
	Paint_End,

	// Key / Char
	Key,
	Char,
}

Item_Callback :: #type proc(^Context, ^Item, Call) -> int

Item_Node :: struct {
	parent: ^Item,
	
	// list
	head: ^Item,
	tail: ^Item,

	// neighbor
	prev: ^Item,
	next: ^Item,
}

Item :: struct {
	handle: rawptr, // item handle (allocated by ctx)
	userdata: rawptr, // user passable data
	callback: Item_Callback, // callback that can be used to do things based on events
	callback_class: Item_Callback, // callback that can include default behaviour

	// node info
	parent: ^Item,
	item_list: dll.List,
	item_node: dll.Node,

	// unique id + next hashes on collisions
	id: Id,
	hash_node: dll.Node,

	sort_children: bool,
	ignore_all: bool, // settable ignore status (wont allow finding the item)
	ignore_self: bool, // only ignore the current element, not its children
	toggle: bool, // persistent state
	last_frame_touched_index: uint,

	layout: Layout, // which layout mode this item uses
	z_index: int, // changes order of children iteration (will effect mouse interaction)
	auto_height: bool,

	// paint info you can query while painting
	paint_index: int,

	// rectangle information
	bounds: RectF, // final bounds that was computed
	bounds_with: RectF, // layout with - final rect that was consumed
	bounds_inf: RectF, // pushes all rects to inf

	// layout info
	layout_offset: V2,
	layout_margin: f32,
	layout_size: V2, // width/height
	layout_ratio: V2, // TODO could be merged to somewhere else
	layout_custom: bool,
	layout_flow: bool,

	// cut info
	cut_self: Cut, // how the item will cut from the rect
	cut_children: Cut, // state that the children will inherit
	cut_gap: f32, // how much to insert a gap after a cut

	// flow self info
	// 1-12 sizing - 0 default == 12
	// column info: default, middle, large based on "media" size
	flow: int,
	
	// flow parent info
	flow_row_gap: f32, // gaps horizontally
	flow_column_gap: f32, // gaps vertically
	flow_height: f32, // height all flow rows should have
	flow_index: int, // temporary offset for layouting
	flow_y: int, // temporary offset for layouting

	scrollbar: Scrollbar_State,
	tooltip: Tooltip_State,

	// persistent data per item - queryable after end_layout
	anim: Animation,
}

// animation that updates every update frame
// in unit space (0.0 -> 1.0)
Animation :: struct {
	hot: f32, // increases when an item is currently being hovered
	active: f32, // increases when an item is acted upon
	trigger: f32, // value that decreases till 0 - useful for short lived triggers like particles
	toggle: f32, // toggleable boolean that stays alive per frame that lerps to the bool (0-1) or (1-0)

	parent_hot: f32, // parent or children hovered
}

////////////////////////////////////////////////////////////////////////////////
// CONTEXT MANAGEMENT
////////////////////////////////////////////////////////////////////////////////

@private
context_clear_data :: proc(ctx: ^Context) #no_bounds_check {
	ctx.hot_item = 0
}

context_init :: proc(ctx: ^Context, item_capacity, buffer_capacity: int) {
	pool_init(&ctx.item_pool, item_capacity)
	fmt.eprintln("ITEM POOL BITMAP COUNT", len(ctx.item_pool.bitmap))
	ctx.item_links = make([]dll.List, MAX_BUCKETS)
	ctx.item_sort = make([]^Item, item_capacity)

	ctx.arena_bytes = make([]byte, buffer_capacity)
	mem.arena_init(&ctx.arena, ctx.arena_bytes)

	ctx.stage = .Process

	context_clear_data(ctx)
	context_clear_state(ctx)
}

context_destroy :: proc(ctx: ^Context) {
	delete(ctx.arena_bytes)
	delete(ctx.item_links)
	delete(ctx.item_sort)
	pool_destroy(&ctx.item_pool)
}

////////////////////////////////////////////////////////////////////////////////
// INPUT CONTROL
////////////////////////////////////////////////////////////////////////////////

@private
add_input_event :: proc(ctx: ^Context, event: Input_Event) #no_bounds_check {
	if ctx.event_count == MAX_INPUT_EVENTS {
		return
	}

	ctx.events[ctx.event_count] = event
	ctx.event_count += 1
}

@private
clear_input_events :: proc(ctx: ^Context) {
	ctx.event_count = 0
	ctx.scroll = {}
}

set_cursor_handle_callback :: proc(ctx: ^Context, callback: Cursor_Handle_Callback) {
	ctx.cursor_handle_callback = callback
}

get_cursor :: #force_inline proc(ctx: ^Context) -> I2 {
	return ctx.cursor
}

get_cursor_start :: #force_inline proc(ctx: ^Context) -> I2 {
	return ctx.cursor_start
}

get_cursor_delta :: #force_inline proc(ctx: ^Context) -> I2 {
	return ctx.cursor - ctx.cursor_start
}

get_cursor_delta_frame :: #force_inline proc(ctx: ^Context) -> I2 {
	return ctx.cursor_delta_frame
}

set_button :: proc(ctx: ^Context, button: Mouse_Button, enabled: bool) {
	if enabled {
		incl(&ctx.buttons, button)
	} else {
		if ctx.button_ignore != nil && (button in ctx.buttons) {
			ctx.button_ignore = nil
		}

		excl(&ctx.buttons, button)
	}
}

button_pressed :: proc(ctx: ^Context, button: Mouse_Button) -> bool {
	return button not_in ctx.last_buttons && button in ctx.buttons
}

button_released :: proc(ctx: ^Context, button: Mouse_Button) -> bool {
	return button in ctx.last_buttons && button not_in ctx.buttons
}

set_key :: proc(ctx: ^Context, key: string) {
	add_input_event(ctx, { key, 0, .Key })
}

set_char :: proc(ctx: ^Context, value: rune) {
	add_input_event(ctx, { "", value, .Char })
}

// // fetch or set the toggle map item id based state
// // can be called per frame
// toggle_get :: proc(ctx: ^Context, item: ^Item) {
// 	if state, ok := ctx.toggle_map[item.id]; ok {
// 		item.toggle = state
// 	} else {
// 		ctx.toggle_map[item.id] = {}
// 	}
// }

// // switch the preexisting switch
// toggle_switch :: proc(ctx: ^Context, item: ^Item) {
// 	if state, ok := &ctx.toggle_map[item.id]; ok {
// 		state^ = !state^
// 	}
// }

// // set the preexisting switch
// toggle_set :: proc(ctx: ^Context, item: ^Item, to: bool) {
// 	ctx.toggle_map[item.id] = to
// }

////////////////////////////////////////////////////////////////////////////////
// STAGES
////////////////////////////////////////////////////////////////////////////////

// starts the layouting stage - resets per frame arrays
// elements can be spawned after this call
begin_layout :: proc(ctx: ^Context, width, height: int) -> ^Item {
	assert(ctx.stage == .Process)
	context_clear_data(ctx)
	ctx.stage = .Layout
	free_all(mem.arena_allocator(&ctx.arena))
	ctx.frame_index += 1

	ctx.root = item_make(ctx, nil, gen_id(nil, "root"))
	ctx.root.layout = .Absolute
	ctx.root.layout_size = { f32(width), f32(height) }

	ctx.tooltips = item_make(ctx, ctx.root, gen_id(ctx.root, "tooltips"))
	ctx.tooltips.layout = .Absolute
	ctx.tooltips.layout_size = { f32(width), f32(height) }
	ctx.tooltips.callback_class = tooltip_root_callback
	ctx.tooltips.ignore_self = true

	return ctx.root
}

// end the layouting stage - computes sizes, layouts items
// also fetches and updates animation state
end_layout :: proc(ctx: ^Context, dt: f32) #no_bounds_check {
	assert(ctx.stage == .Layout)
	assert(ctx.root != nil)
	ctx.dt = dt

	compute_size(ctx, ctx.root)
	arrange(ctx, ctx.root, nil, 0)

	update_hot_item(ctx, ctx.root)

	ctx.stage = .Post_Layout

	item_animate_recursive(ctx, ctx.root, dt)

	update_recursive(ctx, ctx.root)
	paint_recursive(ctx, ctx.root)
}

item_animate_recursive :: proc(ctx: ^Context, p: ^Item, dt: f32) {
	p.anim.hot = clamp(p.anim.hot + (p.id == ctx.hot_item ? dt : -dt), 0, 1)
	p.anim.active = clamp(p.anim.active + (p.id == ctx.active_item ? dt : -dt), 0, 1)
	p.anim.trigger = max(p.anim.trigger - dt, 0)

	if p.toggle {
		p.anim.toggle = min(p.anim.toggle + dt, 1)
	} else {
		p.anim.toggle = max(p.anim.toggle - dt, 0)
	}

	// find child that may be clicked
	hot := find_hot_recursive(ctx, p)
	p.anim.parent_hot = clamp(p.anim.parent_hot + (hot ? dt : -dt), 0, 1)

	// iterate children too
	iter := dll.iterator_head(p.item_list, Item, "item_node")
	for kid in dll.iterate_next(&iter) {
		item_animate_recursive(ctx, kid, dt)
	}
}

// find the current hot item
@private
update_hot_item :: proc(ctx: ^Context, root: ^Item) {
	item := find_item(ctx, root, f32(ctx.cursor.x), f32(ctx.cursor.y))
	ctx.hot_item = item.id
}

// find an item in the parent tree that is currently "hot"
find_hot_recursive :: proc(ctx: ^Context, item: ^Item) -> bool {
	if item.id == ctx.hot_item {
		return true
	}

	iter := dll.iterator_head(item.item_list, Item, "item_node")
	for kid in dll.iterate_next(&iter) {
		res := find_hot_recursive(ctx, kid)

		if res {
			return true
		}
	}

	return false
}

// do quick map based ID finding of items
@private
temp_find :: proc(ctx: ^Context, id: Id) -> (res: ^Item) {
	list, item, matched := item_lookup(ctx, id)
	return item if matched else nil
}

@private
process_button :: proc(
	ctx: ^Context,
	button: Mouse_Button,
	hot_item: ^Id,
	active_item: ^Id,
	focus_item: ^Id,
) -> bool {
	if button in ctx.buttons {
		hot_item^ = 0
		active_item^ = ctx.hot_item

		if active_item^ != focus_item^ {
			focus_item^ = 0
			ctx.focus_item = 0
		}

		capture := -1
		if active_item^ != 0 {
			diff := time.since(ctx.click_time)
			if diff > CLICK_THRESHOLD {
				ctx.clicks = 0
			}

			ctx.clicks += 1
			ctx.last_click_item = active_item^
			ctx.click_time = time.now()

			active := temp_find(ctx, active_item^)
			ctx.cursor_offset = ctx.cursor - { int(active.bounds.l), int(active.bounds.t) }

			switch button {
			case .Left: capture = item_callback(ctx, active, .Left_Down)
			case .Middle: capture = item_callback(ctx, active, .Middle_Down)
			case .Right: capture = item_callback(ctx, active, .Right_Down)
			}
		}

		// only capture if wanted
		if capture != -1 || ctx.button_ignore != nil {
			ctx.button_ignore = button
			active_item^ = 0
			focus_item^ = 0
			return false
		} else {
			ctx.capture_start[button] = time.now()
			ctx.button_capture = button
			ctx.state = .Capture
			return true
		}
	}

	return false
}

process :: proc(ctx: ^Context) {
	// fmt.eprintln("~~~~~~~~~~~~~~~PROCESS~~~~~~~~~~~~~~~~~~~~~~")

	assert(ctx.stage != .Layout)
	if ctx.stage == .Process {
		update_hot_item(ctx, ctx.root)
	}
	ctx.stage = .Process

	if ctx.root == nil {
		clear_input_events(ctx)
		return
	}

	hot_item := ctx.last_hot_item
	active_item := ctx.active_item
	focus_item := ctx.focus_item
	cursor_handle := ctx.cursor_handle

	// send all keyboard events
	if focus_item != 0 {
		for i in 0..<ctx.event_count {
			event := ctx.events[i]
			ctx.active_key = event.key
			ctx.active_char = event.char

			// consume char calls when active
			if event.call == .Char && ctx.consume_focused {
				bytes, size := utf8.encode_rune(event.char)

				for i in 0..<size {
					if ctx.consume_index < MAX_CONSUME {
						ctx.consume[ctx.consume_index] = bytes[i]
						ctx.consume_index += 1
					}
				}
			} else {
				focus := temp_find(ctx, focus_item)
				item_callback(ctx, focus, event.call)
			}

			// TODO this
			// // check for escape
			// if event.key == ctx.escape_key {
			// 	ctx.focus_item = nil
			// }
		}
	} else {
		ctx.focus_item = 0
	}

	// use redirect instead
	if focus_item == 0 {
		item := temp_find(ctx, ctx.focus_redirect_item)

		for i in 0..<ctx.event_count {
			event := ctx.events[i]
			ctx.active_key = event.key
			ctx.active_char = event.char
			item_callback(ctx, item, event.call)
		}
	}

	// apply scroll callback
	if ctx.scroll != {} {
		item := temp_find(ctx, ctx.hot_item)
		for item != nil {
			if item_callback(ctx, item, .Scroll) != CALL_NONE {
				break
			}

			item = item.parent
		}
	}

	clear_input_events(ctx)

	hot := ctx.hot_item
	ctx.clicked_item = 0

	switch ctx.state {
	case .Idle:
		ctx.cursor_start = ctx.cursor

		left := process_button(ctx, .Left, &hot_item, &active_item, &focus_item)
		middle := process_button(ctx, .Middle, &hot_item, &active_item, &focus_item)
		right := process_button(ctx, .Right, &hot_item, &active_item, &focus_item)

		if !left && !right && !middle {
			hot_item = hot
		}

	case .Capture:
		if ctx.button_capture not_in ctx.buttons {
			if active_item != 0 {
				active := temp_find(ctx, active_item)
				switch ctx.button_capture {
				case .Left: item_callback(ctx, active, .Left_Up)
				case .Middle: item_callback(ctx, active, .Middle_Up)
				case .Right: item_callback(ctx, active, .Right_Up)
				}

				if active_item == hot {
					switch ctx.button_capture {
					case .Left: item_callback(ctx, active, .Left_Hot_Up)
					case .Middle: item_callback(ctx, active, .Middle_Hot_Up)
					case .Right: item_callback(ctx, active, .Right_Hot_Up)
					}
					ctx.clicked_item = active_item
				}
			}

			active_item = 0
			ctx.state = .Idle
		} else {
			active := temp_find(ctx, active_item)
			if active_item != 0 {
				switch ctx.button_capture {
				case .Left: item_callback(ctx, active, .Left_Capture)
				case .Middle: item_callback(ctx, active, .Middle_Capture)
				case .Right: item_callback(ctx, active, .Right_Capture)
				}
			}

			hot_item = hot == active_item ? hot : 0
		}
	}

	// look for possible cursor handle
	if hot_item != 0 {
		hot := temp_find(ctx, hot_item)
		wanted_handle := item_callback(ctx, hot, .Cursor_Handle)
		if wanted_handle != -1 {
			ctx.cursor_handle = wanted_handle
		} else {
			// change back to zero - being the default arrow type
			if ctx.cursor_handle != 0 {
				ctx.cursor_handle = 0
			}
		}
	}

	// change of cursor handle
	if cursor_handle != ctx.cursor_handle {
		if ctx.cursor_handle_callback != nil {
			ctx.cursor_handle_callback(ctx, ctx.cursor_handle)
		}
	}

	ctx.cursor_delta_frame = ctx.cursor_last_frame - ctx.cursor
	ctx.cursor_last_frame = ctx.cursor
	ctx.last_hot_item = hot_item
	ctx.active_item = active_item
	ctx.last_buttons = ctx.buttons

	// removes unused items from last frame
	iter := pool_iterator(&ctx.item_pool)
	for item in pool_iterate_next(&iter) {
		if item.last_frame_touched_index < ctx.frame_index {
			modindex := item.id % Id(len(ctx.item_links))
			list := &ctx.item_links[modindex]

			dll.remove(list, &item.hash_node)
			pool_dealloc(&ctx.item_pool, item)
		}
	}
}

context_clear_state :: proc(ctx: ^Context) {
	ctx.last_hot_item = 0
	ctx.active_item = 0
	ctx.focus_item = 0
	ctx.last_click_item = 0
}

update_recursive :: proc(ctx: ^Context, item: ^Item) {
	skip := item_callback(ctx, item, .Update)
	if skip != CALL_NONE || item.item_list.head == nil {
		return
	}

	list := children_list(ctx, item)
	#reverse for kid in list {
		update_recursive(ctx, kid)
	}
}

paint_recursive :: proc(ctx: ^Context, item: ^Item) {
	skip := item_callback(ctx, item, .Paint_Start)

	if skip == CALL_NONE && item.item_list.head != nil {
		list := children_list(ctx, item)
		item.paint_index = 0
		#reverse for kid in list {
			paint_recursive(ctx, kid)
			item.paint_index += 1
		}
	
		item_callback(ctx, item, .Paint_End)
	}
}

////////////////////////////////////////////////////////////////////////////////
// UI DECLARATION
////////////////////////////////////////////////////////////////////////////////

@private
item_lookup :: proc(ctx: ^Context, id: Id) -> (list: ^dll.List, res: ^Item, matched: bool) {
	modindex := id % Id(len(ctx.item_links))
	list = &ctx.item_links[modindex]
	iter := dll.iterator_head(list^, Item, "hash_node")

	for item in dll.iterate_next(&iter) {
		res = item

		if res.id == id {
			matched = true
			return
		}
	}

	return
}

item_get :: proc(ctx: ^Context, id: Id) -> (res: ^Item) {
	list, item, matched := item_lookup(ctx, id)

	if matched {
		res = item
	} else {
		res = pool_alloc(&ctx.item_pool)
		dll.push_back(list, &res.hash_node)
	}

	return
}

item_make :: proc(ctx: ^Context, parent: ^Item, id: Id) -> (child: ^Item) {
	assert(ctx.stage == .Layout)

	child = item_get(ctx, id)

	child.item_list = {}
	child.item_node = {}
	child.flow_index = 0
	child.flow_y = 0
	child.id = id
	child.last_frame_touched_index = ctx.frame_index

	// automatically insert/append element to parent
	if parent != nil {
		child.parent = parent
		child.cut_self = parent.cut_children

		if parent.layout_flow {
			child.layout = .Flow
		}

		dll.push_back(&parent.item_list, &child.item_node)
	}

	return
}

item_callback :: proc(ctx: ^Context, item: ^Item, call: Call) -> (res: int) #no_bounds_check {
	res = CALL_NONE

	if item == nil {
		return
	}

	// user based
	if item.callback != nil {
		if temp := item.callback(ctx, item, call); temp != CALL_NONE {
			res = temp
			return
		}
	}

	// default
	if item.callback_class != nil {
		res = item.callback_class(ctx, item, call)
	}

	return
}

item_alloc :: proc(ctx: ^Context, item: ^Item, data: $T) {
	item.handle = new_clone(data, mem.arena_allocator(&ctx.arena))
}

// TODO checkup focus again
focus :: proc(ctx: ^Context, item: ^Item, consume := false) {
	assert(ctx.stage != .Layout)
	ctx.focus_item = item.id
	ctx.consume_focused = consume
	ctx.consume_index = 0
}

consume_result :: proc(ctx: ^Context) -> string {
	return transmute(string) mem.Raw_String { &ctx.consume[0], ctx.consume_index }
}

consume_decrease :: proc(ctx: ^Context) {
	if ctx.consume_index > 0 {
		ctx.consume_index -= 1
	}
}

focus_redirect :: proc(ctx: ^Context, item: ^Item) {
	ctx.focus_redirect_item = item.id
}

////////////////////////////////////////////////////////////////////////////////
// ITERATION
////////////////////////////////////////////////////////////////////////////////

children_hovered :: proc(item: ^Item, x, y: f32) -> bool {
	iter := dll.iterator_head(item.item_list, Item, "item_node")

	for kid in dll.iterate_next(&iter) {
		if rect.contains(kid.bounds, x, y) {
			return true
		}
	}

	return false
}

// NOTE: uses temp allocator, since item_sort gets reused and the output needs to be stable!
// return z sorted list of children
children_list :: proc(ctx: ^Context, item: ^Item, allocator := context.temp_allocator) -> []^Item {
	count: int

	// loop through children and push items
	iter := dll.iterator_head(item.item_list, Item, "item_node")
	for kid in dll.iterate_next(&iter) {
		ctx.item_sort[count] = kid
		count += 1
	}

	list := ctx.item_sort[:count]

	// optionally sort the children by z_index
	if item.sort_children {
		// sort and return a cloned list
		slice.sort_by(list, proc(a, b: ^Item) -> bool {
			return a.z_index < b.z_index
		})
	}

	return slice.clone(list, allocator)
}

////////////////////////////////////////////////////////////////////////////////
// QUERYING
////////////////////////////////////////////////////////////////////////////////

find_item :: proc(
	ctx: ^Context,
	item: ^Item,
	x, y: f32,
	loc := #caller_location,
) -> ^Item #no_bounds_check {
	if item.ignore_all {
		return item
	}

	list := children_list(ctx, item)
	for kid in list {
		// fetch runtime ignore status
		ignore := kid.ignore_self
		if item_callback(ctx, kid, .Find_Ignore) != CALL_NONE {
			ignore = true
		}

		if !ignore && rect.contains(kid.bounds, x, y) {
			return find_item(ctx, kid, x, y)
		}
	}

	return item
}

get_key :: proc(ctx: ^Context) -> string {
	return ctx.active_key
}

get_char :: proc(ctx: ^Context) -> rune {
	return ctx.active_char
}

contains :: proc(item: ^Item, x, y: f32) -> bool #no_bounds_check {
	return rect.contains(item.bounds, x, y)
}

////////////////////////////////////////////////////////////////////////////////
// OTHER
////////////////////////////////////////////////////////////////////////////////

// true if the item match the active
is_active :: #force_inline proc(ctx: ^Context, item: ^Item) -> bool {
	return ctx.active_item == item.id
}

// true if the item match the hot
is_hot :: #force_inline proc(ctx: ^Context, item: ^Item) -> bool {
	return ctx.last_hot_item == item.id
}

// true if the item match the focused
is_focused :: #force_inline proc(ctx: ^Context, item: ^Item) -> bool {
	return ctx.focus_item == item.id
}

// true if the item match the clicked (HOT_UP)
is_clicked :: #force_inline proc(ctx: ^Context, item: ^Item) -> bool {
	return ctx.clicked_item == item.id
}

// hot + active activeness
hot_active_unit :: proc(item: ^Item, sizing := f32(0.5)) -> f32 #no_bounds_check {
	return item.anim.hot * sizing + item.anim.active * (1-sizing)
}

hot_trigger_unit :: proc(item: ^Item, sizing := f32(0.5)) -> f32 #no_bounds_check {
	return item.anim.hot * sizing + item.anim.trigger * (1-sizing)
}

////////////////////////////////////////////////////////////////////////////////
// LAYOUT & SIZING
////////////////////////////////////////////////////////////////////////////////

// compute the size of an item
compute_size :: proc(ctx: ^Context, item: ^Item) #no_bounds_check {
	// fixed or dynamic user based width/heights
	dyn_width := item_callback(ctx, item, .Dynamic_Width)
	dyn_height := item_callback(ctx, item, .Dynamic_Height)
	item.layout_size.x = dyn_width != CALL_NONE ? f32(dyn_width) : item.layout_size.x
	item.layout_size.y = dyn_height != CALL_NONE ? f32(dyn_height) : item.layout_size.y

	// iterate children
	iter := dll.iterator_head(item.item_list, Item, "item_node")
	for kid in dll.iterate_next(&iter) {
		compute_size(ctx, kid)
	}
}

arrange_item :: proc(item: ^Item, layout: ^RectF, gap: f32) -> (res: RectF) {
  switch item.layout {
	// DEFAULT
	case .Cut:
		// directionality
		switch item.cut_self {
		case .Left: res = rect.cut_left(layout, item.layout_size.x)
		case .Right: res = rect.cut_right(layout, item.layout_size.x)
		case .Top: res = rect.cut_top(layout, item.layout_size.y)
		case .Bottom: res = rect.cut_bottom(layout, item.layout_size.y)
		case .Fill:
			res = layout^
			layout^ = {}
		}

		// apply gapping
		if gap > 0 {
			switch item.cut_self {
			case .Left: layout.l += gap
			case .Right: layout.r -= gap
			case .Top: layout.t += gap
			case .Bottom: layout.b -= gap
			case .Fill:
			}
		}

	case .Absolute:
		res = rect.sized(item.layout_offset, item.layout_size)

	case .Relative:
		off := item.parent != nil ? item.parent.layout_offset : {}
		res = rect.sized(off + item.layout_offset, item.layout_size)

	case .Flow:
		assert(item.parent != nil && item.parent.layout_flow)

		p := item.parent
		current_column := clamp(item.flow == 0 ? 1 : item.flow, 1, 12)

		// indices
		start_index := p.flow_index
		end_index := p.flow_index + current_column

		// increase y
		if end_index > 12 {
			p.flow_index = 0
			p.flow_y += 1
			end_index = p.flow_index + current_column
			start_index = p.flow_index
		} 

		// always increase flow
		p.flow_index += current_column

		// x positions
		x0 := f32(start_index) * rect.width(layout^) / 12
		x1 := f32(end_index) * rect.width(layout^) / 12

		// apply gaps	
		if start_index > 0 {
			x0 += p.flow_row_gap/2
		}
		if end_index < 12 {
			x1 -= p.flow_row_gap/2
		}

		// y position
		y := f32(p.flow_y) * p.flow_height
		y += p.flow_y > 0 ? f32(p.flow_y) * p.flow_column_gap : 0
		y0 := y
		y1 := y + p.flow_height
		
		res = { x0, x1, y0, y1 }
		res = rect.offset(res, layout.l, layout.t)
	}

	return
}

// arrange children
arrange_children_inf :: proc(ctx: ^Context, item: ^Item) {
	item.bounds_inf = rect.RECTF_INF
	iter := dll.iterator_head(item.item_list, Item, "item_node")
	for kid in dll.iterate_next(&iter) {
		arrange(ctx, kid, &item.bounds_with, item.cut_gap)
		rect.inf_push(&item.bounds_inf, kid.bounds.l, kid.bounds.t)
		rect.inf_push(&item.bounds_inf, kid.bounds.t, kid.bounds.b)
	}
}

arrange_item_bounds :: proc(ctx: ^Context, item: ^Item, bounds: RectF) {
	item.bounds = bounds
	item.bounds_with = bounds
	if item.layout_margin > 0 {
		item.bounds_with = rect.margin(item.bounds_with, item.layout_margin)
	}		
}

// layout children with the wanted bounds
arrange_item_recursive :: proc(ctx: ^Context, item: ^Item, bounds: RectF) {
	arrange_item_bounds(ctx, item, bounds)

	// custom layout children
	if item.layout_custom {
		item_callback(ctx, item, .Layout_Custom)
	} else {
		arrange_children_inf(ctx, item)
	}
}

// layouts items based on rect-cut by default or custom ones
arrange :: proc(ctx: ^Context, item: ^Item, layout: ^RectF, gap: f32) {
	bounds := arrange_item(item, layout, gap)
	arrange_item_recursive(ctx, item, bounds)

	if item.auto_height {
		item.bounds.b = item.bounds_inf.b + item.layout_margin
	}
}

////////////////////////////////////////////////////////////////////////////////
// ID gen - same as microui
////////////////////////////////////////////////////////////////////////////////

gen_id_bytes :: proc(parent: ^Item, input: []byte) -> Id {
	seed := parent != nil ? parent.id : 2166136261
	return hash.fnv32a(input, seed)
}

gen_id_string :: proc(parent: ^Item, input: string) -> Id {
	return gen_id_bytes(parent, transmute([]byte) input)
}

gen_id :: proc { gen_id_bytes, gen_id_string }

gen_idf :: proc(parent: ^Item, format: string, args: ..any) -> Id {
	return gen_id_bytes(parent, transmute([]byte) fmt.tprintf(format, ..args))
}

////////////////////////////////////////////////////////////////////////////////
// SPLITTER PANEL EXAMPLE ELEMENTS
////////////////////////////////////////////////////////////////////////////////

// // Persistent state handled by UI context
// Splitter_State :: struct {
// 	ratios: [2]f32,
// }

// // Panel that holds the slider + 2 elements
// Splitter_Panel :: struct {
// 	vertical: bool,
// 	ratios_start: [2]f32,
// 	slider: ^Splitter_Slider,
// }

// // Slider which will effect the ratio of the elements
// Splitter_Slider :: struct {
// 	state: ^Splitter_State,
// }

// splitter_slider_callback :: proc(ctx: ^Context, item: ^Item, call: Call) -> int {
// 	data := cast(^Splitter_Slider) item.handle

// 	#partial switch call {

// 	}

// 	return CALL_NONE
// }

// splitter :: proc(
// 	ctx: ^Context,
// 	parent: ^Item,
// 	vertical: bool,
// 	ratios_start: [2]f32 = { 0.5, 0.5 }
// ) -> (item: ^Item) {
// 	item = item_make(ctx, parent, gen_id(parent, "splitter"))
// 	item_alloc(ctx, item, Splitter_Panel { })
// 	panel_data.vertical = vertical

// 	slider := item_make(ctx, item, gen_id(item, "slider"))
// 	item_alloc(ctx, item, Splitter_Slider { })
// 	panel_data.slider = slider_data

// 	return
// }
