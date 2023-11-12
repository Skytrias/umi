package umi

import "core:fmt"
import "core:math"
import "core:intrinsics"
import "core:testing"

Bitmap :: u32
BITMAP_BITS :: 32

Pool :: struct($T: typeid) {
	bitmap: []Bitmap,
	data: []T,
}

pool_init :: proc(pool: ^Pool($T), data_count: int) {
	pool.data = make([]T, data_count)
	bitmap_count := int(math.ceil(f32(data_count) / BITMAP_BITS))
	pool.bitmap = make([]Bitmap, bitmap_count)

	for i in 0..<len(pool.bitmap) {
		pool.bitmap[i] = max(Bitmap)
	}
}

pool_destroy :: proc(pool: ^Pool($T)) {
	delete(pool.bitmap)
	delete(pool.data)
}

pool_alloc :: proc(pool: ^Pool($T)) -> ^T {
	for i in 0..<len(pool.bitmap) {
		b := &pool.bitmap[i]

		if b^ != 0 {
			// find available spot
			bit_index := intrinsics.count_trailing_zeros(b^)

			// inverse the bit
			b^ &= ~(1 << bit_index)

			// return the data spot
			offset := Bitmap(i) * BITMAP_BITS + bit_index
			// fmt.eprintln("INSERT AT", offset)
			return &pool.data[offset]
		}
	}

	return nil
}

pool_dealloc :: proc(pool: ^Pool($T), ptr: ^T) {
	if ptr == nil {
		return
	}

	block_index := int(uintptr(ptr) - uintptr(raw_data(pool.data))) / size_of(T)
	pool.data[block_index] = {}

	bitmap_index := block_index / BITMAP_BITS
	bit_offset := block_index % BITMAP_BITS

	// fmt.eprintln("REMOVE FROM", bitmap_index, "at offset", bit_offset)
	pool.bitmap[bitmap_index] |= (1 << Bitmap(bit_offset))
}

pool_slots_used :: proc(p: ^Pool($T)) -> (res: int) {
	for i in 0..<len(p.bitmap) {
		res += int(intrinsics.count_zeros(p.bitmap[i]))
	}

	return
}

Pool_Iterator :: struct($T: typeid) {
	pool: ^Pool(T),
	bitmap_index: int,
	curr: Bitmap,
}

pool_iterator :: proc(pool: ^Pool($T)) -> (res: Pool_Iterator(T)) {
	res.pool = pool
	res.bitmap_index = pool_next_used_bitmap(pool, 0)
	res.curr = res.bitmap_index == -1 ? 0 : ~pool.bitmap[res.bitmap_index]
	return
}

// returns the next bitmap with a set slot
@private
pool_next_used_bitmap :: proc(pool: ^Pool($T), start_index: int) -> (res: int) {
	res = -1

	for i in start_index..<len(pool.bitmap) {
		bitmap := pool.bitmap[i]
		
		// check if any bits are unset
		if bitmap != max(Bitmap) {
			res = i
			return
		}
	}

	return
}

pool_iterate_next :: proc(iter: ^Pool_Iterator($T)) -> (res: ^T, ok: bool) {
	// check if curr is empty or bitmap index is invalid
	if iter.curr == 0 || iter.bitmap_index == -1 {
		return
	}

	last_set_bit := intrinsics.count_trailing_zeros(iter.curr)
	offset := Bitmap(iter.bitmap_index) * BITMAP_BITS + last_set_bit
	res = &iter.pool.data[offset]
	ok = true

	iter.curr &= iter.curr - 1

	// if now empty set to next bitmap index with set bits
	if iter.curr == 0 {
		iter.bitmap_index = pool_next_used_bitmap(iter.pool, iter.bitmap_index + 1)
		iter.curr = iter.bitmap_index == -1 ? 0 : ~iter.pool.bitmap[iter.bitmap_index]
	}

	return
}

// @test
// test_pool_alloc_and_dealloc :: proc(t: ^testing.T) {
// 	pool: Pool(int)
// 	pool_init(&pool, 32)
// 	testing.expect(t, len(pool.bitmap) == 1)

// 	testing.expect(t, ~pool.bitmap[0] == 0x00)
// 	d1 := pool_alloc(&pool)
// 	d1^ = 100
// 	testing.expect(t, ~pool.bitmap[0] == 0x01)
// 	d2 := pool_alloc(&pool)
// 	d2^ = 200
// 	testing.expect(t, ~pool.bitmap[0] == 0x03)

// 	pool_dealloc(&pool, d1)
// 	testing.expect(t, ~pool.bitmap[0] == 0x02)
	
// 	pool_dealloc(&pool, d2)
// 	testing.expect(t, ~pool.bitmap[0] == 0x00)
// }

// @test
// test_p_iteration :: proc(t: ^testing.T) {
// 	pool: Pool(int)
// 	pool_init(&pool, 64)

// 	testing.expect(t, len(pool.bitmap) == 2)
// 	testing.expect(t, pool_next_used_bitmap(&pool, 0) == -1)
	
// 	pool_alloc(&pool)^ = 100
// 	pool_alloc(&pool)^ = 200

// 	pool.bitmap[1] = ~u32(0x03)
// 	pool.data[32] = 300
// 	pool.data[33] = 400

// 	iter := pool_iterator(&pool)
// 	testing.log(t, iter)

// 	count: int
// 	testing.log(t, "ITERATE")
// 	for ptr in pool_iterate_next(&iter) {
// 		testing.log(t, "DATA", ptr, ptr^)
// 		count += 1
// 	}

// 	testing.expect(t, count == 4)
// }