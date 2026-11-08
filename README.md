# lua2id

lua2id password hashing and a secure random number generator for roblox, written in luau.

- matches the official argon2 spec (rfc-9106), so hashes work with other argon2 libraries
- strictly typed, with no warnings under either luau type solver
- native-compiled: a default hash takes about 0.5 seconds

## install

copy `src/lua2id` into `ReplicatedStorage`

## usage

```lua
local lua2id = require(game:GetService("ReplicatedStorage").lua2id)

-- hash a password (a random salt is generated for you)
local stored = lua2id.hash("hunter2")

-- check a password later
if lua2id.verify(stored, "hunter2") then
	print("correct!")
end
```

### options

```lua
lua2id.hash("hunter2", {
	memory_cost = 19456, -- KiB of memory (default 19 MiB)
	time_cost = 2,       -- passes over memory (default 2)
	parallelism = 1,     -- lanes (default 1)
	yield_budget = 1/120 -- yield every ~8 ms so the server doesn't freeze
})
```

### random numbers

```lua
local csprng = lua2id.csprng

csprng.random()              -- float in [0, 1)
csprng.random_int(1, 6)      -- integer in [1, 6]
csprng.random_number(0, 10)  -- float in [0, 10)
csprng.random_bytes(32)      -- buffer of 32 random bytes
csprng.random_hex(16)        -- "9f3a0c..."
csprng.random_string(24)     -- alphanumeric string
csprng.add_entropy(buf)      -- mix in extra randomness
```

## tips

- **hash on the server, never the client.**
- **use `yield_budget` on live servers** so a hash doesn't stall the game.
- **only verify hashes you stored yourself.** the cost settings are read from the hash string.
