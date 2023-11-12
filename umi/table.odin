package umi

import dll "core:container/intrusive/list"
import "core:slice"
import "../rect"

////////////////////////////////////////////////////////////////////////////////
// Table layouting implementation
// header
// ---
// content
// ---
// footer
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Design
// - always sticky header / footer (only content may scroll)
// - always fixed size
// - always insert your own items - no defaults
////////////////////////////////////////////////////////////////////////////////

Table_Options :: struct {
	header_height: f32,
	footer_height: f32,
	column_widths: []f32,
}

Table_Root :: struct {
	using options: Table_Options,
}

Table_Row :: struct {
	root: ^Item,
}

// layout items left to right based on column widths
table_layout_row :: proc(ctx: ^Context, item: ^Item, root: ^Table_Root) {
	b := item.bounds_with
	iter := dll.iterator_head(item.item_list, Item, "item_node")

	kid_index := 0
	for kid in dll.iterate_next(&iter) {
		width := root.column_widths[kid_index]
		bounds := rect.cut_left(&b, width)
		arrange_item_recursive(ctx, kid, bounds)
		b.l += item.cut_gap

		kid_index += 1
	}	
}

table_root_callback :: proc(ctx: ^Context, item: ^Item, event: Call) -> int {
	data := cast(^Table_Root) item.handle
	
	#partial switch event {
		
	}

	return CALL_NONE
}

table_header_callback :: proc(ctx: ^Context, item: ^Item, event: Call) -> int {
	data := cast(^Table_Root) item.parent.handle

	#partial switch event {
	case .Layout_Custom:
		table_layout_row(ctx, item, data)
	}

	return CALL_NONE
}

table :: proc(
	ctx: ^Context, 
	parent: ^Item,
	options: Table_Options,
) -> (root, header, content, footer: ^Item) {
	root = item_make(ctx, parent, gen_id(parent, "rootzzz"))
	root.callback_class = table_root_callback
	item_alloc(ctx, root, Table_Root {
		options = options,
		column_widths = slice.clone(options.column_widths, context.temp_allocator),
	})

	root.cut_children = .Top

	header = item_make(ctx, root, gen_id(root, "header"))
	header.callback_class = table_header_callback
	header.layout_custom = true
	header.layout_size.y = options.header_height

	root.cut_children = .Bottom

	footer = item_make(ctx, root, gen_id(root, "footer"))
	footer.layout_size.y = options.footer_height

	root.cut_children = .Fill

	content = item_make(ctx, root, gen_id(root, "content"))
	content.cut_children = .Top

	return
}

table_row_callback :: proc(ctx: ^Context, item: ^Item, event: Call) -> int {
	data := cast(^Table_Row) item.handle

	#partial switch event {
	case .Layout_Custom:
		root := cast(^Table_Root) data.root.handle
		table_layout_row(ctx, item, root)
	}

	return CALL_NONE
}

// a horizontal row which will custom layout its children from left to right based on the widths
// NOTE: no default ids generated - do your own
table_row :: proc(
	ctx: ^Context,
	parent: ^Item, // should be the Table_Element.Content item
	id: Id,
	root: ^Item,
	height: f32,
) -> (item: ^Item) {
	item = item_make(ctx, parent, id)
	item.callback_class = table_row_callback
	item.layout_custom = true
	item.layout_size.y = height
	item_alloc(ctx, item, Table_Row { root })
	return
}