--!strict
--!native
--!optimize 2

const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

const encode_map = buffer.fromstring(alphabet)
const decode_map: buffer = (function()
	const map = buffer.create(256)
	buffer.fill(map, 0, 0xff)
	for i = 0, 63 do
		buffer.writeu8(map, buffer.readu8(encode_map, i), i)
	end
	return map
end)()

local function base64_encode(input: buffer): string
	const len = buffer.len(input)
	const out = buffer.create((len * 4 + 2) // 3)
	local o = 0
	local i = 0

	while i + 3 <= len do
		const n = bit32.bor(
			bit32.lshift(buffer.readu8(input, i), 16),
			bit32.lshift(buffer.readu8(input, i + 1), 8),
			buffer.readu8(input, i + 2)
		)
		buffer.writeu8(out, o, buffer.readu8(encode_map, bit32.rshift(n, 18)))
		buffer.writeu8(out, o + 1, buffer.readu8(encode_map, bit32.band(bit32.rshift(n, 12), 63)))
		buffer.writeu8(out, o + 2, buffer.readu8(encode_map, bit32.band(bit32.rshift(n, 6), 63)))
		buffer.writeu8(out, o + 3, buffer.readu8(encode_map, bit32.band(n, 63)))
		i += 3
		o += 4
	end

	const rest = len - i
	if rest == 1 then
		const n = buffer.readu8(input, i)
		buffer.writeu8(out, o, buffer.readu8(encode_map, bit32.rshift(n, 2)))
		buffer.writeu8(out, o + 1, buffer.readu8(encode_map, bit32.band(bit32.lshift(n, 4), 63)))
	elseif rest == 2 then
		const n = bit32.bor(bit32.lshift(buffer.readu8(input, i), 8), buffer.readu8(input, i + 1))
		buffer.writeu8(out, o, buffer.readu8(encode_map, bit32.rshift(n, 10)))
		buffer.writeu8(out, o + 1, buffer.readu8(encode_map, bit32.band(bit32.rshift(n, 4), 63)))
		buffer.writeu8(out, o + 2, buffer.readu8(encode_map, bit32.band(bit32.lshift(n, 2), 63)))
	end

	return buffer.tostring(out)
end

local function base64_decode(input: string): buffer?
	const len = #input
	if len % 4 == 1 then
		return nil
	end

	const src = buffer.fromstring(input)
	const out = buffer.create(len * 3 // 4)
	local acc = 0
	local bits = 0
	local o = 0

	for i = 0, len - 1 do
		const value = buffer.readu8(decode_map, buffer.readu8(src, i))
		if value == 0xff then
			return nil
		end
		acc = bit32.bor(bit32.lshift(acc, 6), value)
		bits += 6
		if bits >= 8 then
			bits -= 8
			buffer.writeu8(out, o, bit32.band(bit32.rshift(acc, bits), 0xff))
			o += 1
			acc = bit32.band(acc, bit32.lshift(1, bits) - 1)
		end
	end

	if acc ~= 0 then
		return nil
	end
	
	return out
end

local function hex_encode(input: buffer): string
	const len = buffer.len(input)
	const parts = table.create(len)
	
	for i = 0, len - 1 do
		parts[i + 1] = string.format("%02x", buffer.readu8(input, i))
	end
	
	return table.concat(parts)
end

local function hex_decode(input: string): buffer?
	if #input % 2 ~= 0 or string.find(input, "[^%x]") then
		return nil
	end
	
	const out = buffer.create(#input // 2)
	for i = 0, #input // 2 - 1 do
		buffer.writeu8(out, i, tonumber(string.sub(input, i * 2 + 1, i * 2 + 2), 16) :: number)
	end
	
	return out
end

const encoding = table.freeze({
	base64_encode = base64_encode,
	base64_decode = base64_decode,
	hex_encode = hex_encode,
	hex_decode = hex_decode,
})

export type encoding = typeof(encoding)

return encoding
