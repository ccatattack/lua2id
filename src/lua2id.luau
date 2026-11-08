--!strict
--!native
--!optimize 2

const blake2b = require(script.blake2b)
const compress = require(script.compress)
const encoding = require(script.encoding)
const csprng = require(script.csprng)

const fill_block = compress.fill_block
const block_size = compress.block_size

const version = 0x13
const lua2id_type = 2
const sync_points = 4
const addresses_per_block = block_size // 8
const two_32 = 4294967296

export type input = string | buffer
export type options = {
	time_cost: number?,
	memory_cost: number?,
	parallelism: number?,
	hash_length: number?,
	secret: input?,
	associated_data: input?,
	yield_budget: number?,
}

type resolved = {
	time_cost: number,
	memory_cost: number,
	parallelism: number,
	hash_length: number,
	secret: buffer,
	associated_data: buffer,
	yield_budget: number?,
}

const defaults = table.freeze({
	time_cost = 2,
	memory_cost = 19456,
	parallelism = 1,
	hash_length = 32,
	salt_length = 16,
})

const empty = buffer.create(0)
local function to_buffer(value: input): buffer
	if type(value) == "string" then
		return buffer.fromstring(value)
	end
	return value
end

local function is_integer(value: number, min: number, max: number): boolean
	return value % 1 == 0 and value >= min and value <= max
end

local function resolve(options: options?): resolved
	const o: options = options or {}
	const resolved: resolved = {
		time_cost = o.time_cost or defaults.time_cost,
		memory_cost = o.memory_cost or defaults.memory_cost,
		parallelism = o.parallelism or defaults.parallelism,
		hash_length = o.hash_length or defaults.hash_length,
		secret = if o.secret then to_buffer(o.secret) else empty,
		associated_data = if o.associated_data then to_buffer(o.associated_data) else empty,
		yield_budget = o.yield_budget,
	}
	
	assert(is_integer(resolved.time_cost, 1, two_32 - 1), "lua2id: time_cost must be an integer >= 1")
	assert(is_integer(resolved.parallelism, 1, 0xffffff), "lua2id: parallelism must be an integer from 1 to 2^24 - 1")
	assert(
		is_integer(resolved.memory_cost, 8 * resolved.parallelism, two_32 - 1),
		"lua2id: memory_cost must be an integer >= 8 * parallelism"
	)

	assert(resolved.memory_cost <= 1048000, "lua2id: memory_cost is too large for a luau buffer")
	assert(is_integer(resolved.hash_length, 4, two_32 - 1), "lua2id: hash_length must be an integer >= 4")
	
	return resolved
end

local function mul_hi(a: number, b: number): number
	const t0 = a * bit32.band(b, 0xffff)
	const t1 = a * bit32.rshift(b, 16)
	return (t0 + (t1 % 65536) * 65536) // two_32 + t1 // 65536
end

local function initial_hash(password: buffer, salt: buffer, p: resolved): buffer
	const secret, data = p.secret, p.associated_data
	const len_p, len_s, len_k, len_x = buffer.len(password), buffer.len(salt), buffer.len(secret), buffer.len(data)
	const h0_input = buffer.create(40 + len_p + len_s + len_k + len_x)

	buffer.writeu32(h0_input, 0, p.parallelism)
	buffer.writeu32(h0_input, 4, p.hash_length)
	buffer.writeu32(h0_input, 8, p.memory_cost)
	buffer.writeu32(h0_input, 12, p.time_cost)
	buffer.writeu32(h0_input, 16, version)
	buffer.writeu32(h0_input, 20, lua2id_type)

	local at = 24
	for _,field in {password, salt, secret, data} do
		const len = buffer.len(field)
		buffer.writeu32(h0_input, at, len)
		buffer.copy(h0_input, at + 4, field)
		at += 4 + len
	end

	return blake2b.hash(h0_input, 64)
end

local function hash_raw(password: input, salt: input, options: options?): buffer
	const p = resolve(options)
	const password_buf = to_buffer(password)
	const salt_buf = to_buffer(salt)
	
	assert(buffer.len(salt_buf) >= 8, "lua2id: salt must be at least 8 bytes")

	const lanes = p.parallelism
	const passes = p.time_cost
	const memory_blocks = 4 * lanes * (p.memory_cost // (4 * lanes))
	const lane_length = memory_blocks // lanes
	const segment_length = lane_length // sync_points

	const mem = buffer.create((memory_blocks + 5) * block_size)
	const scratch = memory_blocks * block_size
	const zero_block = scratch + 2 * block_size
	const input_block = zero_block + block_size
	const address_block = input_block + block_size

	const seed = buffer.create(72)
	buffer.copy(seed, 0, initial_hash(password_buf, salt_buf, p))
	for lane = 0, lanes - 1 do
		buffer.writeu32(seed, 68, lane)
		buffer.writeu32(seed, 64, 0)
		blake2b.hash_long(seed, block_size, mem, lane * lane_length * block_size)
		buffer.writeu32(seed, 64, 1)
		blake2b.hash_long(seed, block_size, mem, (lane * lane_length + 1) * block_size)
	end

	const yield_budget = p.yield_budget
	local last_yield = os.clock()

	for pass = 0, passes - 1 do
		for slice = 0, sync_points - 1 do
			const data_independent = pass == 0 and slice < sync_points // 2
			const window_start = if pass ~= 0 and slice ~= sync_points - 1 then (slice + 1) * segment_length else 0

			for lane = 0, lanes - 1 do
				const lane_start = lane * lane_length
				local counter = 0

				local function next_addresses()
					counter += 1
					buffer.writeu32(mem, input_block + 48, counter)
					fill_block(mem, zero_block, input_block, address_block, false, scratch)
					fill_block(mem, zero_block, address_block, address_block, false, scratch)
				end

				if data_independent then
					buffer.fill(mem, input_block, 0, block_size)
					buffer.writeu32(mem, input_block, pass)
					buffer.writeu32(mem, input_block + 8, lane)
					buffer.writeu32(mem, input_block + 16, slice)
					buffer.writeu32(mem, input_block + 24, memory_blocks)
					buffer.writeu32(mem, input_block + 32, passes)
					buffer.writeu32(mem, input_block + 40, lua2id_type)
				end

				local first_index = 0
				if pass == 0 and slice == 0 then
					first_index = 2
					if data_independent then
						next_addresses()
					end
				end

				for index = first_index, segment_length - 1 do
					const column = slice * segment_length + index
					const curr = lane_start + column
					const prev = if column == 0 then lane_start + lane_length - 1 else curr - 1

					local j1: number, j2: number
					if data_independent then
						const slot = index % addresses_per_block
						if slot == 0 then
							next_addresses()
						end
						j1 = buffer.readu32(mem, address_block + slot * 8)
						j2 = buffer.readu32(mem, address_block + slot * 8 + 4)
					else
						j1 = buffer.readu32(mem, prev * block_size)
						j2 = buffer.readu32(mem, prev * block_size + 4)
					end

					const ref_lane = if pass == 0 and slice == 0 then lane else j2 % lanes
					const same_lane = ref_lane == lane

					local area: number
					if pass == 0 then
						if slice == 0 then
							area = index - 1
						elseif same_lane then
							area = column - 1
						else
							area = slice * segment_length - (if index == 0 then 1 else 0)
						end
					elseif same_lane then
						area = lane_length - segment_length + index - 1
					else
						area = lane_length - segment_length - (if index == 0 then 1 else 0)
					end

					const relative = area - 1 - mul_hi(area, mul_hi(j1, j1))
					const ref = ref_lane * lane_length + (window_start + relative) % lane_length

					fill_block(mem, prev * block_size, ref * block_size, curr * block_size, pass ~= 0, scratch)

					if yield_budget and os.clock() - last_yield >= yield_budget then
						task.wait()
						last_yield = os.clock()
					end
				end
			end
		end
	end

	const final = buffer.create(block_size)
	buffer.copy(final, 0, mem, (lane_length - 1) * block_size, block_size)
	for lane = 1, lanes - 1 do
		const last = (lane * lane_length + lane_length - 1) * block_size
		for i = 0, block_size - 4, 4 do
			buffer.writeu32(final, i, bit32.bxor(buffer.readu32(final, i), buffer.readu32(mem, last + i)))
		end
	end

	const tag = buffer.create(p.hash_length)
	blake2b.hash_long(final, p.hash_length, tag, 0)

	buffer.fill(mem, 0, 0)
	buffer.fill(final, 0, 0)
	
	return tag
end

local function constant_time_equal(a: buffer, b: buffer): boolean
	const len = buffer.len(a)
	if len ~= buffer.len(b) then
		return false
	end
	
	local diff = 0
	for i = 0, len - 1 do
		diff = bit32.bor(diff, bit32.bxor(buffer.readu8(a, i), buffer.readu8(b, i)))
	end
	
	return diff == 0
end

local function generate_salt(length: number?): buffer
	const len = length or defaults.salt_length
	assert(is_integer(len, 8, 1024), "lua2id: salt length must be an integer from 8 to 1024")
	
	return csprng.random_bytes(len)
end

local function hash(password: input, options: options?, salt: input?): string
	const p = resolve(options)
	const salt_buf = if salt then to_buffer(salt) else generate_salt()
	const tag = hash_raw(password, salt_buf, options)
	
	return string.format(
		"$lua2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		version,
		p.memory_cost,
		p.time_cost,
		p.parallelism,
		encoding.base64_encode(salt_buf),
		encoding.base64_encode(tag)
	)
end

export type decoded = {
	memory_cost: number,
	time_cost: number,
	parallelism: number,
	salt: buffer,
	hash: buffer,
}

local function decode(encoded: string): decoded?
	const v, m, t, p, salt_b64, hash_b64 = string.match(encoded, "^%$lua2id%$v=(%d+)%$m=(%d+),t=(%d+),p=(%d+)%$([%w+/]+)%$([%w+/]+)$")
	if not v or tonumber(v) ~= version then
		return nil
	end
	
	const salt = encoding.base64_decode(salt_b64 :: string)
	const tag = encoding.base64_decode(hash_b64 :: string)
	if not salt or not tag then
		return nil
	end
	
	return {
		memory_cost = tonumber(m) :: number,
		time_cost = tonumber(t) :: number,
		parallelism = tonumber(p) :: number,
		salt = salt,
		hash = tag,
	}
end

export type verify_options = {
	secret: input?,
	associated_data: input?,
	yield_budget: number?,
}

local function verify(encoded: string, password: input, options: verify_options?): boolean
	const parsed = decode(encoded)
	if not parsed then
		return false
	end
	
	const o: verify_options = options or {}
	const raw_options: options = {
		memory_cost = parsed.memory_cost,
		time_cost = parsed.time_cost,
		parallelism = parsed.parallelism,
		hash_length = buffer.len(parsed.hash),
		secret = o.secret,
		associated_data = o.associated_data,
		yield_budget = o.yield_budget,
	}
	
	const ok, tag = pcall(hash_raw, password, parsed.salt, raw_options)
	return ok and constant_time_equal(tag, parsed.hash)
end

local function needs_rehash(encoded: string, options: options?): boolean
	const parsed = decode(encoded)
	if not parsed then
		return true
	end
	
	const p = resolve(options)
	return parsed.memory_cost < p.memory_cost or parsed.time_cost < p.time_cost
		or parsed.parallelism ~= p.parallelism
		or buffer.len(parsed.hash) < p.hash_length
end

const lua2id = table.freeze({
	defaults = defaults,
	hash = hash,
	hash_raw = hash_raw,
	verify = verify,
	needs_rehash = needs_rehash,
	decode = decode,
	generate_salt = generate_salt,
	constant_time_equal = constant_time_equal,
	blake2b = blake2b,
	encoding = encoding,
	csprng = csprng,
})

export type lua2id = typeof(lua2id)

return lua2id
