package umi

import "core:fmt"
import "../rect"

Tooltip_Direction :: enum {
	Right,
	Left,
	Top,
	Bottom
}

Tooltip_Fade :: enum {
	None,
	
	Fading_In,
	Faded_In,

	Idle,
	
	Fading_Out,
	Faded_Out,
}

Tooltip_State :: struct {
	running: Tooltip_Fade,
	fade_counter: f32,
	counter: f32,
}

Tooltip :: struct {
	// at which location the tooltip should appear
	next_to: ^Item, // next to which item
	at: V2, // or at which position - ignores direction
	direction: Tooltip_Direction,

	// options	
	size: V2, // size of the tooltip
	gap: f32, // gap to the origin
	fade_in: f32,
	fade_out: f32,

	// persistent
	state: Tooltip_State,
}

tooltip_root_callback :: proc(ctx: ^Context, item: ^Item, event: Call) -> int {
	#partial switch event {
	case .Paint_Start:
		// fmt.eprintln("TOOLTIP ROOT PAINTING", item.bounds)
	}

	return CALL_NONE
}

tooltip_alpha :: proc(item: ^Item, tooltip: ^Tooltip) -> f32 {
	if tooltip.next_to != nil {
		return item.tooltip.counter
	} else {
		return 0
	}
}

tooltip_callback :: proc(ctx: ^Context, item: ^Item, event: Call) -> int {
	data := cast(^Tooltip) item.handle

	#partial switch event {
	case .Layout_Custom:
		if data.next_to != nil {
			b := data.next_to.bounds
			if b == {} {
				return 0
			}

			w2 := data.size.x / 2
			h2 := data.size.y / 2
			x, y := rect.center(data.next_to.bounds)

			switch data.direction {
			case .Right: 
				b.l = b.r + data.gap
				b.r = b.l + data.size.x

				b.t = y - h2
				b.b = y + h2
			case .Left:
				b.r = b.l - data.gap
				b.l = b.r - data.size.x

				b.t = y - h2
				b.b = y + h2
			case .Top:
				b.b = b.t - data.gap
				b.t = b.b - data.size.y

				// center of the parent
				b.l = x - w2
				b.r = x + w2
			case .Bottom:
				b.t = b.b + data.gap
				b.b = b.t + data.size.y

				// center of the parent
				b.l = x - w2
				b.r = x + w2
			}

			// TODO clamp but also dont intersect the next_to.bounds
			rect.clamp_within(&b, rect.margin(item.parent.bounds, 5))
			arrange_item_bounds(ctx, item, b)
			arrange_children_inf(ctx, item)
		} else {
			b := rect.sized(data.at, data.size)
			arrange_children_inf(ctx, item)
		}

	case .Update:
		if data.next_to != nil {
			state := &item.tooltip
			
			if data.fade_in != 0 || data.fade_out != 0 {
				switch state.running {
				case .None:
					if data.next_to.anim.hot != 0 {
						if data.fade_in == 0 {
							// skip fading in
							state.running = .Faded_In
							state.counter = 1
						} else {
							state.running = .Fading_In
							state.fade_counter = 0
						}
					}
				
				case .Fading_In:
					if state.fade_counter < data.fade_in {
						state.fade_counter = min(state.fade_counter + ctx.dt, data.fade_in)

						if state.fade_counter == data.fade_in {
							state.running = .Faded_In
						}

						// shutdown early if already exited
						if data.next_to.anim.hot == 0 {
							state.running = .None
						}
					}					

				case .Faded_In:
					state.counter = min(state.counter + ctx.dt, 1)

					if state.counter == 1 {
						state.fade_counter = 0
						state.running = .Idle
					}

				case .Idle:
					if data.next_to.anim.hot == 0 {
						state.running = data.fade_out == 0 ? .Faded_Out : .Fading_Out
						state.fade_counter = 0
					}
				
				case .Fading_Out:
					// back to idle if hovered again
					if data.next_to.anim.hot != 0 {
						state.running = .Idle
					}

					if state.fade_counter < data.fade_out {
						state.fade_counter = min(state.fade_counter + ctx.dt, data.fade_out)

						if state.fade_counter == data.fade_out {
							state.running = .Faded_Out
						}
					}

				case .Faded_Out:
					state.counter = max(state.counter - ctx.dt, 0)

					if state.counter == 0 {
						state.fade_counter = 0
						state.running = .None
					}
				}
			} else {
				state.counter = data.next_to.anim.hot
			}
		}
	}

	return CALL_NONE
}

tooltip_spawn_next_to :: proc(
	ctx: ^Context, 
	next_to: ^Item, 
	id: Id,
	direction: Tooltip_Direction,
	size: V2,
) -> (item: ^Item) {
	item = item_make(ctx, ctx.tooltips, id)
	item.callback_class = tooltip_callback
	item.layout_custom = true
	item_alloc(ctx, item, Tooltip {
		next_to = next_to,
		direction = direction,
		size = size,
		gap = 10,

		fade_in = 2.5,
		// fade_out = 2.5,
	})

	return 
}

// tooltip_spawn_at :: proc(
// 	ctx: ^Context, 
// 	position: V2,
// 	size: V2,
// ) -> (item: ^Item) {
// 	item = item_make(ctx, &ctx.tooltips)
// 	item.callback_class = tooltip_callback
// 	item.layout_custom = true

// 	data := alloc_typed(ctx, item, Tooltip)
// 	data.at = position
// 	data.size = size

// 	return 
// }
