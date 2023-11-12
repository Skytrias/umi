package umi

import dll "core:container/intrusive/list"
import "../rect"

////////////////////////////////////////////////////////////////////////////////
// SCROLLBAR PANEL & SLIDER EXAMPLE ELEMENTS
////////////////////////////////////////////////////////////////////////////////

Scrollbar_State :: struct {
	// set by user
	vertical: bool,
	enabled: bool,
	auto_hide: bool,

	scroll_position: f32,
	thumb_position: f32,
	thumb_size: f32,

	// frame layout state
	maximum: f32,
	page_full: f32,
	page_margin: f32,
	margin: f32,

	// drag state
	drag_offset: f32,

	// wether to ignore rendering the scrollbar next frame
	ignore_next_frame: bool,
}

Scrollbar_Panel :: struct {
	sliders: [2]^Item,
	rest: ^Item,
}

scrollbar_slider_inactive :: proc(slider: ^Item) -> bool {
	using slider.scrollbar
	return page_margin >= maximum || maximum <= 0 || page_margin == 0
}

scrollbar_slider_position_set :: proc(slider: ^Item, to: f32) {
	old := slider.scrollbar.scroll_position
	slider.scrollbar.scroll_position = to

	if old != slider.scrollbar.scroll_position {
		// TODO message
	}
}

// clamp the scroll position to 0/page size
scrollbar_slider_position_clamp :: proc(slider: ^Item) -> (diff: f32) {
	diff = max(slider.scrollbar.maximum - slider.scrollbar.page_margin, 0)

	if slider.scrollbar.scroll_position < 0 {
		slider.scrollbar.scroll_position = 0
	} else if slider.scrollbar.scroll_position > f32(diff) {
		slider.scrollbar.scroll_position = f32(diff)
	}

	return
}

scrollbar_slider_thumb_position :: proc(item: ^Item) {
	diff := scrollbar_slider_position_clamp(item)

	if diff == 0 {
		item.scrollbar.thumb_position = 0
		return
	}

	size := item.scrollbar.vertical ? rect.height(item.bounds) : rect.width(item.bounds)
	item.scrollbar.thumb_position = item.scrollbar.scroll_position / diff * (size - item.scrollbar.thumb_size)
}

scrollbar_slider_thumb_size :: proc(item: ^Item) {
	size := item.scrollbar.vertical ? rect.height(item.bounds) : rect.width(item.bounds)
	if item.scrollbar.ignore_next_frame {
		// just full size
		item.scrollbar.thumb_size = size
	} else {
		item.scrollbar.thumb_size = max(50, size * item.scrollbar.page_margin / item.scrollbar.maximum)
	}
}

// current page size
scrollbar_slider_max_and_page :: proc(
	comp: ^Item,
	slider: ^Item,
) {
	slider.scrollbar.maximum = slider.scrollbar.vertical ? rect.height(comp.bounds_inf) : rect.width(comp.bounds_inf)
	slider.scrollbar.page_full = slider.scrollbar.vertical ? rect.height(comp.bounds) : rect.width(comp.bounds)
	slider.scrollbar.page_margin = slider.scrollbar.page_full - comp.layout_margin * 2
	slider.scrollbar.margin = comp.layout_margin * 2
}

children_offset :: proc(item: ^Item, x, y: f32) {
	iter := dll.iterator_head(item.item_list, Item, "item_node")

	for kid in dll.iterate_next(&iter) {
		kid.bounds.t -= y
		kid.bounds.b -= y
		children_offset(kid, x, y)
	}
}

scrollbar_panel_callback :: proc(ctx: ^Context, item: ^Item, event: Call) -> int {
	data := cast(^Scrollbar_Panel) item.handle

	#partial switch event {
	case .Scroll:
		if ctx.scroll.y != 0 {
			v := data.sliders[1]
			scrollbar_slider_position_set(v, v.scrollbar.scroll_position + f32(ctx.scroll.y) * 20)
			scrollbar_slider_position_clamp(v)
			return 1
		}

	case .Layout_Custom:
		b := item.bounds_with
		h := data.sliders[0]
		if !h.scrollbar.enabled || (h.scrollbar.auto_hide && h.scrollbar.ignore_next_frame) {
			// h.ignore_self = true
		} else {
			h.bounds = rect.cut_bottom(&b, 20)
		}

		v := data.sliders[1]
		if !v.scrollbar.enabled || (v.scrollbar.auto_hide && v.scrollbar.ignore_next_frame) {
			// v.ignore_self = true
		} else {
			v.bounds = rect.cut_right(&b, 20)
		}

		// layout rest as normal
		arrange_item_recursive(ctx, data.rest, b)

		// 1 frame behind but okay
		{
			// vscrollbar
			scrollbar_slider_max_and_page(data.rest, v)
			v.scrollbar.ignore_next_frame = scrollbar_slider_inactive(v)
			scrollbar_slider_thumb_size(v)
			scrollbar_slider_thumb_position(v)

			// hscrollbar
			scrollbar_slider_max_and_page(data.rest, h)
			h.scrollbar.ignore_next_frame = scrollbar_slider_inactive(h)
			scrollbar_slider_thumb_size(h)
			scrollbar_slider_thumb_position(h)
		}

		// finally offset
		children_offset(data.rest, h.scrollbar.scroll_position, v.scrollbar.scroll_position)
	}

	return CALL_NONE
}

scrollbar_slider_callback :: proc(ctx: ^Context, item: ^Item, event: Call) -> int {
	// state := &item.scrollbar
	// using state

	#partial switch event {
	case .Left_Down:
		if item.scrollbar.vertical {
			item.scrollbar.drag_offset = item.scrollbar.thumb_position - f32(ctx.cursor.y)
		} else {
			item.scrollbar.drag_offset = item.scrollbar.thumb_position - f32(ctx.cursor.x)
		}

	case .Left_Capture:
		// thumb positioning
		cursor_offset := item.scrollbar.vertical ? f32(ctx.cursor.y) : f32(ctx.cursor.x)
		thumb_position := item.scrollbar.drag_offset + cursor_offset

		// actual scroll offset
		thumb_diff := item.scrollbar.page_full - item.scrollbar.thumb_size
		item.scrollbar.scroll_position = thumb_position / thumb_diff * (item.scrollbar.maximum - item.scrollbar.page_margin)
	}

	return CALL_NONE
}

Scrollbar_Options :: struct {
	henabled: bool,
	hauto_hide: bool,
	venabled: bool,
	vauto_hide: bool,
}

scrollbar :: proc(
	ctx: ^Context,
	parent: ^Item,
	text: string,
	options: Scrollbar_Options,
) -> (item, rest, vscroll, hscroll: ^Item) {
	item = item_make(ctx, parent, gen_id_simple(parent, text))
	item.callback_class = scrollbar_panel_callback
	item.layout_custom = true

	// spawn vertical scrollbar
	vscroll = item_make(ctx, item, gen_id_simple(item, "vertical"))
	vscroll.callback_class = scrollbar_slider_callback
	vscroll.scrollbar.enabled = options.venabled
	vscroll.scrollbar.vertical = true
	vscroll.scrollbar.auto_hide = options.vauto_hide

	// spawn horizontal scrollbar
	hscroll = item_make(ctx, item, gen_id_simple(item, "horizontal"))
	hscroll.callback_class = scrollbar_slider_callback
	hscroll.scrollbar.enabled = options.henabled
	hscroll.scrollbar.vertical = false
	hscroll.scrollbar.auto_hide = options.hauto_hide

	rest = item_make(ctx, item, gen_id_simple(item, "rest"))

	item_alloc(ctx, item, Scrollbar_Panel {
		{ hscroll, vscroll },
		rest,
	})

	return
}
