--!strict
-- CRC-32 (IEEE 802.3). Used to detect typos / truncation in pasted codes.
-- NOTE: this is an integrity check, not a security measure. The server
-- re-validates every decoded payload regardless.

local TABLE: { number } = {}
for i = 0, 255 do
	local c = i
	for _ = 1, 8 do
		if bit32.band(c, 1) == 1 then
			c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
		else
			c = bit32.rshift(c, 1)
		end
	end
	TABLE[i] = c
end

local function crc32(s: string): number
	local crc = 0xFFFFFFFF
	for i = 1, #s do
		local byte = string.byte(s, i)
		crc = bit32.bxor(TABLE[bit32.band(bit32.bxor(crc, byte), 0xFF)], bit32.rshift(crc, 8))
	end
	return bit32.bxor(crc, 0xFFFFFFFF)
end

return function(s: string): string
	return string.format("%08x", crc32(s))
end
