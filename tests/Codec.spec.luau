local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Base64 = require(Shared.Codec.Base64)
local Lzw = require(Shared.Codec.Lzw)
local crc32 = require(Shared.Codec.Crc32)
local ExportCode = require(Shared.Codec.ExportCode)
local Presets = require(Shared.Presets)

local function randomBytes(n: number, alphabet: number?): string
	local out = table.create(n)
	for i = 1, n do
		out[i] = string.char(math.random(0, (alphabet or 256) - 1))
	end
	return table.concat(out)
end

return {
	["base64 round-trips every length"] = function(t)
		for n = 0, 40 do
			local s = randomBytes(n)
			t.eq(Base64.decode(Base64.encode(s)), s, "length " .. n)
		end
	end,
	["base64 rejects bad characters"] = function(t)
		t.eq(Base64.decode("ab$d"), nil)
		t.eq(Base64.decode("abcde"), nil, "length % 4 == 1 is invalid")
	end,
	["crc32 matches the standard check value"] = function(t)
		t.eq(crc32("123456789"), "cbf43926")
	end,
	["lzw round-trips text and binary"] = function(t)
		t.eq(Lzw.decompress(Lzw.compress("")), "")
		t.eq(Lzw.decompress(Lzw.compress("a")), "a")
		local s = string.rep("TOBEORNOTTOBEORTOBEORNOT", 50)
		t.eq(Lzw.decompress(Lzw.compress(s)), s)
		local b = randomBytes(5000)
		t.eq(Lzw.decompress(Lzw.compress(b)), b)
	end,
	["lzw survives a dictionary reset"] = function(t)
		-- enough varied input to emit > 65k codes
		local s = randomBytes(150000, 64)
		t.eq(Lzw.decompress(Lzw.compress(s), 1e7), s)
	end,
	["lzw refuses decompression bombs"] = function(t)
		local s = string.rep("a", 100000)
		t.eq(Lzw.decompress(Lzw.compress(s), 1000), nil)
	end,
	["export code round-trips a moveset"] = function(t)
		local code = ExportCode.encode("moveset", Presets.StarterMoveset)
		t.ok(string.sub(code, 1, 7) == "JJR1.M.", "prefix")
		local kind, data = ExportCode.decode(code)
		t.eq(kind, "moveset")
		t.eq(data.name, Presets.StarterMoveset.name)
		t.eq(#data.moves, #Presets.StarterMoveset.moves)
	end,
	["export code tolerates whitespace from pasting"] = function(t)
		local code = ExportCode.encode("vfx", Presets.StarterVfx.spark)
		local spaced = string.sub(code, 1, 10) .. "\n  " .. string.sub(code, 11)
		local kind = ExportCode.decode(spaced)
		t.eq(kind, "vfx")
	end,
	["export code detects tampering"] = function(t)
		local code = ExportCode.encode("vfx", Presets.StarterVfx.spark)
		local i = 12
		local c = string.sub(code, i, i)
		local tampered = string.sub(code, 1, i - 1) .. (if c == "A" then "B" else "A") .. string.sub(code, i + 1)
		local kind, err = ExportCode.decode(tampered)
		t.eq(kind, nil)
		t.ok(type(err) == "string")
		t.eq((ExportCode.decode("hello")), nil)
		t.eq((ExportCode.decode(string.rep("A", 100000))), nil)
	end,
}
