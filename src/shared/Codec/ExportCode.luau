--!strict
-- Share codes for movesets and VFX.
--
--   JJR1.<kind>.<base64(lzw(json))>.<crc32 of the base64 body>
--
-- kind: "M" = moveset (may embed the VFX it uses), "V" = single VFX effect.
--
-- Decoding only produces a plain Lua table. It never runs anything. The
-- caller MUST pass the result through the matching validator before using it.

local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Parent.Config)
local Base64 = require(script.Parent.Base64)
local Lzw = require(script.Parent.Lzw)
local crc32 = require(script.Parent.Crc32)

local ExportCode = {}

export type Kind = "moveset" | "vfx"

local KIND_TO_CHAR: { [string]: string } = { moveset = "M", vfx = "V" }
local CHAR_TO_KIND: { [string]: Kind } = { M = "moveset", V = "vfx" }

function ExportCode.encode(kind: Kind, data: any): string
	local json = HttpService:JSONEncode({ v = Config.FormatVersion, data = data })
	local body = Base64.encode(Lzw.compress(json))
	return string.format("%s%d.%s.%s.%s", Config.CodePrefix, Config.FormatVersion, KIND_TO_CHAR[kind], body, crc32(body))
end

-- Returns (kind, data) on success or (nil, errorMessage) on failure.
function ExportCode.decode(code: string): (Kind?, any)
	if type(code) ~= "string" then
		return nil, "Code must be text."
	end
	code = string.gsub(code, "%s", "") -- people paste with line breaks
	if #code > Config.MaxCodeLength then
		return nil, "Code is too long."
	end

	local version, kindChar, body, checksum = string.match(code, "^" .. Config.CodePrefix .. "(%d+)%.(%a)%.([%w%-_]+)%.(%x+)$")
	if not version then
		return nil, "That doesn't look like a JujutsuRampage code."
	end
	local kind = CHAR_TO_KIND[kindChar :: string]
	if not kind then
		return nil, "Unknown code type."
	end
	if tonumber(version) ~= Config.FormatVersion then
		-- Migration hooks for future format versions go here.
		return nil, "This code was made with an unsupported version."
	end
	if crc32(body :: string) ~= string.lower(checksum :: string) then
		return nil, "Code is damaged or incomplete (checksum mismatch)."
	end

	local raw = Base64.decode(body :: string)
	if not raw then
		return nil, "Code is damaged (bad characters)."
	end
	local json = Lzw.decompress(raw, Config.MaxCodeLength * 8)
	if not json then
		return nil, "Code is damaged (could not decompress)."
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok or type(decoded) ~= "table" or decoded.data == nil then
		return nil, "Code is damaged (bad data)."
	end
	return kind, decoded.data
end

return ExportCode
