--!strict
-- Standard Base64 (RFC 4648) with '-' and '_' replaced to stay URL/chat safe.

local Base64 = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local ENC: { string } = {}
local DEC: { [number]: number } = {}
for i = 1, 64 do
	local c = string.sub(ALPHABET, i, i)
	ENC[i - 1] = c
	DEC[string.byte(c)] = i - 1
end

function Base64.encode(input: string): string
	local out = table.create(math.ceil(#input / 3) * 4)
	local n = #input
	for i = 1, n, 3 do
		local a, b, c = string.byte(input, i, i + 2)
		local triple = bit32.lshift(a, 16) + bit32.lshift(b or 0, 8) + (c or 0)
		table.insert(out, ENC[bit32.extract(triple, 18, 6)])
		table.insert(out, ENC[bit32.extract(triple, 12, 6)])
		if b then
			table.insert(out, ENC[bit32.extract(triple, 6, 6)])
		end
		if c then
			table.insert(out, ENC[bit32.extract(triple, 0, 6)])
		end
	end
	return table.concat(out)
end

-- Returns nil if the input contains characters outside the alphabet.
function Base64.decode(input: string): string?
	local out = table.create(math.floor(#input * 3 / 4))
	local n = #input
	if n % 4 == 1 then
		return nil
	end
	for i = 1, n, 4 do
		local v = 0
		local count = 0
		for j = i, math.min(i + 3, n) do
			local d = DEC[string.byte(input, j)]
			if d == nil then
				return nil
			end
			v = bit32.lshift(v, 6) + d
			count += 1
		end
		v = bit32.lshift(v, 6 * (4 - count))
		table.insert(out, string.char(bit32.extract(v, 16, 8)))
		if count >= 3 then
			table.insert(out, string.char(bit32.extract(v, 8, 8)))
		end
		if count == 4 then
			table.insert(out, string.char(bit32.extract(v, 0, 8)))
		end
	end
	return table.concat(out)
end

return Base64
