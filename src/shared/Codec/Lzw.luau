--!strict
-- Byte-oriented LZW. Codes are written as fixed 16-bit big-endian values; the
-- dictionary resets when full. JSON movesets typically shrink to ~40-55%.

local Lzw = {}

local MAX_CODE = 65535

function Lzw.compress(input: string): string
	if input == "" then
		return ""
	end
	local dict: { [string]: number } = {}
	for i = 0, 255 do
		dict[string.char(i)] = i
	end
	local nextCode = 256
	local out = {}
	local w = ""
	for i = 1, #input do
		local c = string.sub(input, i, i)
		local wc = w .. c
		if dict[wc] ~= nil then
			w = wc
		else
			local code = dict[w]
			table.insert(out, string.char(bit32.rshift(code, 8), bit32.band(code, 0xFF)))
			if nextCode <= MAX_CODE then
				dict[wc] = nextCode
				nextCode += 1
			else
				-- reset dictionary
				dict = {}
				for j = 0, 255 do
					dict[string.char(j)] = j
				end
				nextCode = 256
			end
			w = c
		end
	end
	local code = dict[w]
	table.insert(out, string.char(bit32.rshift(code, 8), bit32.band(code, 0xFF)))
	return table.concat(out)
end

-- Returns nil on malformed input. `maxOutput` guards against decompression bombs.
function Lzw.decompress(input: string, maxOutput: number?): string?
	if input == "" then
		return ""
	end
	if #input % 2 ~= 0 then
		return nil
	end
	local limit = maxOutput or 1_000_000
	local dict: { [number]: string } = {}
	for i = 0, 255 do
		dict[i] = string.char(i)
	end
	local nextCode = 256
	local out = {}
	local total = 0

	local function readCode(i: number): number
		local hi, lo = string.byte(input, i, i + 1)
		return hi * 256 + lo
	end

	local first = readCode(1)
	if first > 255 then
		return nil
	end
	local w = dict[first]
	table.insert(out, w)
	total += #w

	for i = 3, #input, 2 do
		local k = readCode(i)
		local entry: string
		if dict[k] ~= nil then
			entry = dict[k]
		elseif k == nextCode then
			entry = w .. string.sub(w, 1, 1)
		else
			return nil
		end
		total += #entry
		if total > limit then
			return nil
		end
		table.insert(out, entry)
		if nextCode <= MAX_CODE then
			dict[nextCode] = w .. string.sub(entry, 1, 1)
			nextCode += 1
			w = entry
		else
			-- mirror the compressor's reset: the dictionary is rebuilt and the
			-- next code is emitted fresh against the base dictionary
			dict = {}
			for j = 0, 255 do
				dict[j] = string.char(j)
			end
			nextCode = 256
			w = entry
		end
	end
	return table.concat(out)
end

return Lzw
