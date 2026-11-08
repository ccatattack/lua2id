--!strict
--!native
--!optimize 2

const two_32 = 4294967296
const block_size = 1024

local function gb(
	a_lo: number, a_hi: number,
	b_lo: number, b_hi: number,
	c_lo: number, c_hi: number,
	d_lo: number, d_hi: number
): (number, number, number, number, number, number, number, number)
	local t0: number, t1: number, mm: number

	t0 = a_lo * bit32.band(b_lo, 0xffff)
	t1 = a_lo * bit32.rshift(b_lo, 16)
	mm = t0 + bit32.band(t1, 0xffff) * 65536
	t0 = a_lo + b_lo + 2 * bit32.band(mm, 0xffffffff)
	a_hi = bit32.band(a_hi + b_hi + 2 * (mm // two_32 + t1 // 65536) + t0 // two_32, 0xffffffff)
	a_lo = bit32.band(t0, 0xffffffff)
	
	t0 = bit32.bxor(d_lo, a_lo)
	d_lo = bit32.bxor(d_hi, a_hi)
	d_hi = t0

	
	t0 = c_lo * bit32.band(d_lo, 0xffff)
	t1 = c_lo * bit32.rshift(d_lo, 16)
	mm = t0 + bit32.band(t1, 0xffff) * 65536
	t0 = c_lo + d_lo + 2 * bit32.band(mm, 0xffffffff)
	c_hi = bit32.band(c_hi + d_hi + 2 * (mm // two_32 + t1 // 65536) + t0 // two_32, 0xffffffff)
	c_lo = bit32.band(t0, 0xffffffff)
	
	t0 = bit32.bxor(b_lo, c_lo)
	t1 = bit32.bxor(b_hi, c_hi)
	b_lo = bit32.bor(bit32.rshift(t0, 24), bit32.lshift(t1, 8))
	b_hi = bit32.bor(bit32.rshift(t1, 24), bit32.lshift(t0, 8))

	
	t0 = a_lo * bit32.band(b_lo, 0xffff)
	t1 = a_lo * bit32.rshift(b_lo, 16)
	mm = t0 + bit32.band(t1, 0xffff) * 65536
	t0 = a_lo + b_lo + 2 * bit32.band(mm, 0xffffffff)
	a_hi = bit32.band(a_hi + b_hi + 2 * (mm // two_32 + t1 // 65536) + t0 // two_32, 0xffffffff)
	a_lo = bit32.band(t0, 0xffffffff)
	
	t0 = bit32.bxor(d_lo, a_lo)
	t1 = bit32.bxor(d_hi, a_hi)
	d_lo = bit32.bor(bit32.rshift(t0, 16), bit32.lshift(t1, 16))
	d_hi = bit32.bor(bit32.rshift(t1, 16), bit32.lshift(t0, 16))

	
	t0 = c_lo * bit32.band(d_lo, 0xffff)
	t1 = c_lo * bit32.rshift(d_lo, 16)
	mm = t0 + bit32.band(t1, 0xffff) * 65536
	t0 = c_lo + d_lo + 2 * bit32.band(mm, 0xffffffff)
	c_hi = bit32.band(c_hi + d_hi + 2 * (mm // two_32 + t1 // 65536) + t0 // two_32, 0xffffffff)
	c_lo = bit32.band(t0, 0xffffffff)
	
	t0 = bit32.bxor(b_lo, c_lo)
	t1 = bit32.bxor(b_hi, c_hi)
	b_lo = bit32.bor(bit32.lshift(t0, 1), bit32.rshift(t1, 31))
	b_hi = bit32.bor(bit32.lshift(t1, 1), bit32.rshift(t0, 31))

	return a_lo, a_hi, b_lo, b_hi, c_lo, c_hi, d_lo, d_hi
end

local function permute(z: buffer, base: number, column: boolean)
	const pair_stride = if column then 128 else 16

	local v0_lo, v0_hi = buffer.readu32(z, base), buffer.readu32(z, base + 4)
	local v1_lo, v1_hi = buffer.readu32(z, base + 8), buffer.readu32(z, base + 12)
	
	local at = base + pair_stride
	local v2_lo, v2_hi = buffer.readu32(z, at), buffer.readu32(z, at + 4)
	local v3_lo, v3_hi = buffer.readu32(z, at + 8), buffer.readu32(z, at + 12)
	at += pair_stride
	
	local v4_lo, v4_hi = buffer.readu32(z, at), buffer.readu32(z, at + 4)
	local v5_lo, v5_hi = buffer.readu32(z, at + 8), buffer.readu32(z, at + 12)
	at += pair_stride
	
	local v6_lo, v6_hi = buffer.readu32(z, at), buffer.readu32(z, at + 4)
	local v7_lo, v7_hi = buffer.readu32(z, at + 8), buffer.readu32(z, at + 12)
	at += pair_stride
	
	local v8_lo, v8_hi = buffer.readu32(z, at), buffer.readu32(z, at + 4)
	local v9_lo, v9_hi = buffer.readu32(z, at + 8), buffer.readu32(z, at + 12)
	at += pair_stride
	
	local v10_lo, v10_hi = buffer.readu32(z, at), buffer.readu32(z, at + 4)
	local v11_lo, v11_hi = buffer.readu32(z, at + 8), buffer.readu32(z, at + 12)
	at += pair_stride
	
	local v12_lo, v12_hi = buffer.readu32(z, at), buffer.readu32(z, at + 4)
	local v13_lo, v13_hi = buffer.readu32(z, at + 8), buffer.readu32(z, at + 12)
	at += pair_stride
	
	local v14_lo, v14_hi = buffer.readu32(z, at), buffer.readu32(z, at + 4)
	local v15_lo, v15_hi = buffer.readu32(z, at + 8), buffer.readu32(z, at + 12)

	
	v0_lo, v0_hi, v4_lo, v4_hi, v8_lo, v8_hi, v12_lo, v12_hi =
		gb(v0_lo, v0_hi, v4_lo, v4_hi, v8_lo, v8_hi, v12_lo, v12_hi)
	v1_lo, v1_hi, v5_lo, v5_hi, v9_lo, v9_hi, v13_lo, v13_hi =
		gb(v1_lo, v1_hi, v5_lo, v5_hi, v9_lo, v9_hi, v13_lo, v13_hi)
	v2_lo, v2_hi, v6_lo, v6_hi, v10_lo, v10_hi, v14_lo, v14_hi =
		gb(v2_lo, v2_hi, v6_lo, v6_hi, v10_lo, v10_hi, v14_lo, v14_hi)
	v3_lo, v3_hi, v7_lo, v7_hi, v11_lo, v11_hi, v15_lo, v15_hi =
		gb(v3_lo, v3_hi, v7_lo, v7_hi, v11_lo, v11_hi, v15_lo, v15_hi)
	
	v0_lo, v0_hi, v5_lo, v5_hi, v10_lo, v10_hi, v15_lo, v15_hi =
		gb(v0_lo, v0_hi, v5_lo, v5_hi, v10_lo, v10_hi, v15_lo, v15_hi)
	v1_lo, v1_hi, v6_lo, v6_hi, v11_lo, v11_hi, v12_lo, v12_hi =
		gb(v1_lo, v1_hi, v6_lo, v6_hi, v11_lo, v11_hi, v12_lo, v12_hi)
	v2_lo, v2_hi, v7_lo, v7_hi, v8_lo, v8_hi, v13_lo, v13_hi =
		gb(v2_lo, v2_hi, v7_lo, v7_hi, v8_lo, v8_hi, v13_lo, v13_hi)
	v3_lo, v3_hi, v4_lo, v4_hi, v9_lo, v9_hi, v14_lo, v14_hi =
		gb(v3_lo, v3_hi, v4_lo, v4_hi, v9_lo, v9_hi, v14_lo, v14_hi)

	buffer.writeu32(z, base, v0_lo)
	buffer.writeu32(z, base + 4, v0_hi)
	buffer.writeu32(z, base + 8, v1_lo)
	buffer.writeu32(z, base + 12, v1_hi)
	at = base + pair_stride
	
	buffer.writeu32(z, at, v2_lo)
	buffer.writeu32(z, at + 4, v2_hi)
	buffer.writeu32(z, at + 8, v3_lo)
	buffer.writeu32(z, at + 12, v3_hi)
	at += pair_stride
	
	buffer.writeu32(z, at, v4_lo)
	buffer.writeu32(z, at + 4, v4_hi)
	buffer.writeu32(z, at + 8, v5_lo)
	buffer.writeu32(z, at + 12, v5_hi)
	at += pair_stride
	
	buffer.writeu32(z, at, v6_lo)
	buffer.writeu32(z, at + 4, v6_hi)
	buffer.writeu32(z, at + 8, v7_lo)
	buffer.writeu32(z, at + 12, v7_hi)
	at += pair_stride
	
	buffer.writeu32(z, at, v8_lo)
	buffer.writeu32(z, at + 4, v8_hi)
	buffer.writeu32(z, at + 8, v9_lo)
	buffer.writeu32(z, at + 12, v9_hi)
	at += pair_stride
	
	buffer.writeu32(z, at, v10_lo)
	buffer.writeu32(z, at + 4, v10_hi)
	buffer.writeu32(z, at + 8, v11_lo)
	buffer.writeu32(z, at + 12, v11_hi)
	at += pair_stride
	
	buffer.writeu32(z, at, v12_lo)
	buffer.writeu32(z, at + 4, v12_hi)
	buffer.writeu32(z, at + 8, v13_lo)
	buffer.writeu32(z, at + 12, v13_hi)
	at += pair_stride
	
	buffer.writeu32(z, at, v14_lo)
	buffer.writeu32(z, at + 4, v14_hi)
	buffer.writeu32(z, at + 8, v15_lo)
	buffer.writeu32(z, at + 12, v15_hi)
end

local function fill_block(mem: buffer, prev: number, ref: number, dest: number, with_xor: boolean, scratch: number)
	const r = scratch
	const z = scratch + block_size

	if with_xor then
		for i = 0, block_size - 4, 4 do
			const v = bit32.bxor(buffer.readu32(mem, prev + i), buffer.readu32(mem, ref + i))
			buffer.writeu32(mem, z + i, v)
			buffer.writeu32(mem, r + i, bit32.bxor(v, buffer.readu32(mem, dest + i)))
		end
	else
		for i = 0, block_size - 4, 4 do
			const v = bit32.bxor(buffer.readu32(mem, prev + i), buffer.readu32(mem, ref + i))
			buffer.writeu32(mem, z + i, v)
			buffer.writeu32(mem, r + i, v)
		end
	end

	for i = 0, 7 do
		permute(mem, z + i * 128, false)
	end
	
	for i = 0, 7 do
		permute(mem, z + i * 16, true)
	end

	for i = 0, block_size - 4, 4 do
		buffer.writeu32(mem, dest + i, bit32.bxor(buffer.readu32(mem, z + i), buffer.readu32(mem, r + i)))
	end
end

const compress = table.freeze({
	block_size = block_size,
	fill_block = fill_block,
})

export type compress = typeof(compress)

return compress
