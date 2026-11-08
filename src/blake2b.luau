--!strict
--!native
--!optimize 2

const two_32 = 4294967296
const iv_lo: { number } = {
	0xf3bcc908, 0x84caa73b, 0xfe94f82b, 0x5f1d36f1,
	0xade682d1, 0x2b3e6c1f, 0xfb41bd6b, 0x137e2179,
}

const iv_hi: { number } = {
	0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
	0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
}

const sigma: { number } = (function()
	const rows = {
		{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
		{14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
		{11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4},
		{7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8},
		{9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13},
		{2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9},
		{12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11},
		{13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10},
		{6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5},
		{10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0},
	}
	
	const flat: { number } = table.create(12 * 16, 0)
	for round = 0, 11 do
		const row = rows[round % 10 + 1]
		for k = 1, 16 do
			flat[round * 16 + k] = row[k] + 1
		end
	end
	
	return flat
end)()

const h_lo: {number} = table.create(8, 0)
const h_hi: {number} = table.create(8, 0)
const v_lo: {number} = table.create(16, 0)
const v_hi: {number} = table.create(16, 0)
const m_lo: {number} = table.create(16, 0)
const m_hi: {number} = table.create(16, 0)
const tail = buffer.create(128)
const digest = buffer.create(64)

local function mix(a: number, b: number, c: number, d: number, x: number, y: number)
	local a_lo, a_hi = v_lo[a], v_hi[a]
	local b_lo, b_hi = v_lo[b], v_hi[b]
	local c_lo, c_hi = v_lo[c], v_hi[c]
	local d_lo, d_hi = v_lo[d], v_hi[d]
	
	local t0: number, t1: number

	t0 = a_lo + b_lo + m_lo[x]
	a_hi = (a_hi + b_hi + m_hi[x] + t0 // two_32) % two_32
	a_lo = t0 % two_32
	
	t0 = bit32.bxor(d_lo, a_lo)
	d_lo = bit32.bxor(d_hi, a_hi)
	d_hi = t0
	
	t0 = c_lo + d_lo
	c_hi = (c_hi + d_hi + t0 // two_32) % two_32
	c_lo = t0 % two_32
	
	t0 = bit32.bxor(b_lo, c_lo)
	t1 = bit32.bxor(b_hi, c_hi)
	b_lo = bit32.bor(bit32.rshift(t0, 24), bit32.lshift(t1, 8))
	b_hi = bit32.bor(bit32.rshift(t1, 24), bit32.lshift(t0, 8))
	
	t0 = a_lo + b_lo + m_lo[y]
	a_hi = (a_hi + b_hi + m_hi[y] + t0 // two_32) % two_32
	a_lo = t0 % two_32
	
	t0 = bit32.bxor(d_lo, a_lo)
	t1 = bit32.bxor(d_hi, a_hi)
	d_lo = bit32.bor(bit32.rshift(t0, 16), bit32.lshift(t1, 16))
	d_hi = bit32.bor(bit32.rshift(t1, 16), bit32.lshift(t0, 16))
	
	t0 = c_lo + d_lo
	c_hi = (c_hi + d_hi + t0 // two_32) % two_32
	c_lo = t0 % two_32
	
	t0 = bit32.bxor(b_lo, c_lo)
	t1 = bit32.bxor(b_hi, c_hi)
	b_lo = bit32.bor(bit32.lshift(t0, 1), bit32.rshift(t1, 31))
	b_hi = bit32.bor(bit32.lshift(t1, 1), bit32.rshift(t0, 31))

	v_lo[a], v_hi[a] = a_lo, a_hi
	v_lo[b], v_hi[b] = b_lo, b_hi
	v_lo[c], v_hi[c] = c_lo, c_hi
	v_lo[d], v_hi[d] = d_lo, d_hi
end

local function compress(src: buffer, offset: number, counter: number, last: boolean)
	for i = 1, 16 do
		const at = offset + (i - 1) * 8
		m_lo[i] = buffer.readu32(src, at)
		m_hi[i] = buffer.readu32(src, at + 4)
	end
	
	for i = 1, 8 do
		v_lo[i], v_hi[i] = h_lo[i], h_hi[i]
		v_lo[i + 8], v_hi[i + 8] = iv_lo[i], iv_hi[i]
	end

	v_lo[13] = bit32.bxor(v_lo[13], counter % two_32)
	v_hi[13] = bit32.bxor(v_hi[13], counter // two_32)
	
	if last then
		v_lo[15] = bit32.bxor(v_lo[15], 0xffffffff)
		v_hi[15] = bit32.bxor(v_hi[15], 0xffffffff)
	end

	for round = 0, 11 do
		const s = round * 16
		mix(1, 5, 9, 13, sigma[s + 1], sigma[s + 2])
		mix(2, 6, 10, 14, sigma[s + 3], sigma[s + 4])
		mix(3, 7, 11, 15, sigma[s + 5], sigma[s + 6])
		mix(4, 8, 12, 16, sigma[s + 7], sigma[s + 8])
		mix(1, 6, 11, 16, sigma[s + 9], sigma[s + 10])
		mix(2, 7, 12, 13, sigma[s + 11], sigma[s + 12])
		mix(3, 8, 9, 14, sigma[s + 13], sigma[s + 14])
		mix(4, 5, 10, 15, sigma[s + 15], sigma[s + 16])
	end

	for i = 1, 8 do
		h_lo[i] = bit32.bxor(h_lo[i], v_lo[i], v_lo[i + 8])
		h_hi[i] = bit32.bxor(h_hi[i], v_hi[i], v_hi[i + 8])
	end
end

local function hash(input: buffer, out_len: number): buffer
	assert(out_len >= 1 and out_len <= 64 and out_len % 1 == 0, "blake2b: out_len must be an integer from 1 to 64")

	for i = 1, 8 do
		h_lo[i], h_hi[i] = iv_lo[i], iv_hi[i]
	end
	
	h_lo[1] = bit32.bxor(h_lo[1], 0x01010000, out_len)
	const len = buffer.len(input)
	
	local offset = 0
	while len - offset > 128 do
		compress(input, offset, offset + 128, false)
		offset += 128
	end

	buffer.fill(tail, 0, 0)
	buffer.copy(tail, 0, input, offset, len - offset)
	compress(tail, 0, len, true)

	for i = 1, 8 do
		buffer.writeu32(digest, (i - 1) * 8, h_lo[i])
		buffer.writeu32(digest, (i - 1) * 8 + 4, h_hi[i])
	end
	
	const out = buffer.create(out_len)
	buffer.copy(out, 0, digest, 0, out_len)
	
	return out
end

local function hash_long(input: buffer, out_len: number, dest: buffer, dest_offset: number)
	const prefixed = buffer.create(4 + buffer.len(input))
	buffer.writeu32(prefixed, 0, out_len)
	buffer.copy(prefixed, 4, input)

	if out_len <= 64 then
		buffer.copy(dest, dest_offset, hash(prefixed, out_len))
		return
	end

	const links = math.ceil(out_len / 32) - 2
	
	local v = hash(prefixed, 64)
	buffer.copy(dest, dest_offset, v, 0, 32)
	for i = 1, links - 1 do
		v = hash(v, 64)
		buffer.copy(dest, dest_offset + i * 32, v, 0, 32)
	end
	
	buffer.copy(dest, dest_offset + links * 32, hash(v, out_len - links * 32))
end

const blake2b = table.freeze({
	hash = hash,
	hash_long = hash_long,
})

export type blake2b = typeof(blake2b)

return blake2b
