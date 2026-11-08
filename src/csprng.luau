--!strict
--!native
--!optimize 2

const blake2b = require(script.Parent.blake2b)
const encoding = require(script.Parent.encoding)

const key_size = 32
const pool_size = 2048
const output_blocks = math.ceil((key_size + pool_size) / 64)
const reseed_interval = 1024
const guid_count = 4
const jitter_samples = 256
const default_charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

const block_input = buffer.create(key_size + 8)
const pool = buffer.create(pool_size)
local key = buffer.create(key_size)
local position = pool_size
local refills = 0

local function gather_entropy(user_entropy: buffer?)
	const parts: {buffer} = {buffer.fromstring("lua2id.csprng seed v1"), key}

	if game then
		const http_service = game:GetService("HttpService")
		for _ = 1, guid_count do
			table.insert(parts, buffer.fromstring(http_service:GenerateGUID(false)))
		end
	end

	const engine = buffer.create(32)
	const rng = Random.new()
	for i = 0, 7 do
		buffer.writeu32(engine, i * 4, rng:NextInteger(0, 0xffffffff))
	end
	
	table.insert(parts, engine)

	const clocks = buffer.create(24)
	buffer.writef64(clocks, 0, os.clock())
	buffer.writef64(clocks, 8, os.time())
	buffer.writef64(clocks, 16, DateTime.now().UnixTimestampMillis)
	table.insert(parts, clocks)

	const jitter = buffer.create(jitter_samples)
	
	local spin = 0
	for i = 0, jitter_samples - 1 do
		const started = os.clock()
		spin += buffer.len(buffer.create(64 + spin % 1024))
		buffer.writeu8(jitter, i, math.floor((os.clock() - started) * 1e9) % 256)
	end
	
	table.insert(parts, jitter)
	table.insert(parts, buffer.fromstring(tostring({}) .. tostring(newproxy()) .. tostring(coroutine.running())))

	if user_entropy then
		table.insert(parts, user_entropy)
	end

	local total = 0
	for _,part in parts do
		total += 4 + buffer.len(part)
	end
	
	const material = buffer.create(total)
	
	local at = 0
	for _,part in parts do
		buffer.writeu32(material, at, buffer.len(part))
		buffer.copy(material, at + 4, part)
		at += 4 + buffer.len(part)
	end

	const old_key = key
	key = blake2b.hash(material, key_size)
	buffer.fill(old_key, 0, 0)
	buffer.fill(material, 0, 0)
	buffer.fill(engine, 0, 0)
	refills = 0
end

local function refill()
	buffer.copy(block_input, 0, key)
	buffer.fill(key, 0, 0)
	buffer.writeu32(block_input, key_size + 4, 0x72616e64)

	for counter = 0, output_blocks - 1 do
		buffer.writeu32(block_input, key_size, counter)
		const block = blake2b.hash(block_input, 64)
		if counter == 0 then
			key = buffer.create(key_size)
			buffer.copy(key, 0, block, 0, key_size)
			buffer.copy(pool, 0, block, key_size, 64 - key_size)
		else
			const offset = counter * 64 - key_size
			buffer.copy(pool, offset, block, 0, math.min(64, pool_size - offset))
		end
		buffer.fill(block, 0, 0)
	end

	buffer.fill(block_input, 0, 0)
	position = 0
	refills += 1
	if refills % reseed_interval == 0 then
		gather_entropy()
	end
end

local function take(n: number): number
	if position + n > pool_size then
		refill()
	end
	const at = position
	position += n
	return at
end

local function next_u32(): number
	const at = take(4)
	const value = buffer.readu32(pool, at)
	buffer.writeu32(pool, at, 0)
	return value
end

local function uniform(min: number, range: number): number
	if range == 0x100000000 then
		return min + next_u32()
	end
	
	if bit32.band(range, range - 1) == 0 then
		return min + bit32.band(next_u32(), range - 1)
	end
	
	const limit = 0x100000000 - 0x100000000 % range
	
	local value = next_u32()
	while value >= limit do
		value = next_u32()
	end
	
	return min + value % range
end

local function check_integer(name: string, value: number)
	if type(value) ~= "number" or value % 1 ~= 0 or value ~= value or math.abs(value) == math.huge then
		error(`csprng: {name} must be an integer, got {value}`, 3)
	end
end

local function check_finite(name: string, value: number)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		error(`csprng: {name} must be a finite number, got {value}`, 3)
	end
end

local function check_count(name: string, value: number)
	if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > 0x40000000 then
		error(`csprng: {name} must be a positive integer, got {value}`, 3)
	end
end

local function random(): number
	const high = bit32.rshift(next_u32(), 5)
	const low = bit32.rshift(next_u32(), 6)
	return (high * 67108864 + low) * 2 ^ -53
end

local function random_int(min: number, max: number?): number
	check_integer("min", min)
	
	local low, high = 1, min
	if max ~= nil then
		check_integer("max", max)
		low, high = min, max
	end
	
	if high < low then
		error(`csprng: max ({high}) must not be less than min ({low})`, 2)
	end
	
	const range = high - low + 1
	if range > 0x100000000 then
		error(`csprng: range must hold at most 2^32 values, got {range}`, 2)
	end
	
	return uniform(low, range)
end

local function random_number(min: number, max: number?): number
	check_finite("min", min)
	
	local low, high = 0, min
	if max ~= nil then
		check_finite("max", max)
		low, high = min, max
	end
	
	if high < low then
		error(`csprng: max ({high}) must not be less than min ({low})`, 2)
	end
	
	return low + random() * (high - low)
end

local function random_bytes(count: number): buffer
	check_count("count", count)
	const out = buffer.create(count)
	
	local written = 0
	while written < count do
		if position >= pool_size then
			refill()
		end
		
		const n = math.min(count - written, pool_size - position)
		buffer.copy(out, written, pool, position, n)
		buffer.fill(pool, position, 0, n)
		
		written += n
		position += n
	end
	
	return out
end

local function random_hex(length: number): string
	check_count("length", length)
	return string.sub(encoding.hex_encode(random_bytes((length + 1) // 2)), 1, length)
end

local function random_string(length: number, charset: string?): string
	check_count("length", length)
	
	const set = charset or default_charset
	const set_size = #set
	if set_size == 0 then
		error("csprng: charset must not be empty", 2)
	end
	
	const set_buf = buffer.fromstring(set)
	const out = buffer.create(length)
	for i = 0, length - 1 do
		buffer.writeu8(out, i, buffer.readu8(set_buf, uniform(0, set_size)))
	end
	
	return buffer.tostring(out)
end

local function add_entropy(entropy: buffer?)
	if entropy ~= nil and typeof(entropy) ~= "buffer" then
		error(`csprng: entropy must be a buffer or nil, got {typeof(entropy)}`, 2)
	end
	
	gather_entropy(entropy)
	refill()
end

gather_entropy()
refill()

const csprng = table.freeze({
	random = random,
	random_int = random_int,
	random_number = random_number,
	random_bytes = random_bytes,
	random_hex = random_hex,
	random_string = random_string,
	add_entropy = add_entropy,
})

export type csprng = typeof(csprng)

return csprng
