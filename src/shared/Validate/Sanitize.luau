--!strict
-- Small, paranoid helpers that turn arbitrary decoded JSON into values of a
-- known shape. They never error; bad input becomes the default.

local Sanitize = {}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function Sanitize.number(v: any, default: number, min: number?, max: number?): number
	if not finite(v) then
		return default
	end
	if min and v < min then
		v = min
	end
	if max and v > max then
		v = max
	end
	return v
end

function Sanitize.int(v: any, default: number, min: number?, max: number?): number
	return math.floor(Sanitize.number(v, default, min, max) + 0.5)
end

function Sanitize.bool(v: any, default: boolean): boolean
	if type(v) == "boolean" then
		return v
	end
	return default
end

function Sanitize.enum(v: any, options: { string }, default: string): string
	if type(v) == "string" and table.find(options, v) then
		return v
	end
	return default
end

-- Strips control characters / rich text markup and trims to length.
function Sanitize.text(v: any, maxLength: number, default: string?): string
	if type(v) ~= "string" then
		return default or ""
	end
	local s = string.gsub(v, "[%c<>]", "")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	local length = utf8.len(s)
	if length == nil then
		return default or ""
	end
	if length > maxLength then
		local cut = utf8.offset(s, maxLength + 1) :: number
		s = string.sub(s, 1, cut - 1)
	end
	return s
end

-- Asset ids are stored as digit-only strings. Accepts numbers, "123",
-- "rbxassetid://123" and "https://www.roblox.com/asset/?id=123".
function Sanitize.asset(v: any): string
	if type(v) == "number" and finite(v) and v > 0 then
		return string.format("%d", v)
	end
	if type(v) ~= "string" then
		return ""
	end
	local digits = string.match(v, "^%s*(%d+)%s*$") or string.match(v, "rbxassetid://(%d+)") or string.match(v, "[?&]id=(%d+)")
	if digits and #digits <= 20 then
		return digits
	end
	return ""
end

-- Short identifier used for VFX library keys.
function Sanitize.id(v: any): string
	if type(v) ~= "string" then
		return ""
	end
	if #v > 16 or not string.match(v, "^[%w_%-]+$") then
		return ""
	end
	return v
end

function Sanitize.vector(v: any, n: number, default: { number }, min: number?, max: number?): { number }
	local out = table.create(n)
	local src = if type(v) == "table" then v else default
	for i = 1, n do
		out[i] = Sanitize.number(src[i], default[i] or 0, min, max)
	end
	return out
end

-- An array of tables, truncated to maxCount. Non-table entries are dropped.
function Sanitize.array(v: any, maxCount: number): { any }
	local out = {}
	if type(v) ~= "table" then
		return out
	end
	for i = 1, maxCount do
		local item = v[i]
		if item == nil then
			break
		end
		if type(item) == "table" then
			table.insert(out, item)
		end
	end
	return out
end

-- Colour: {r,g,b} 0-255.
function Sanitize.color(v: any, default: { number }): { number }
	return Sanitize.vector(v, 3, default, 0, 255)
end

-- ColorSequence: { {t, r, g, b}, ... } with t ascending from 0 to 1.
function Sanitize.colorSeq(v: any, default: { { number } }, maxKeypoints: number): { { number } }
	local items = Sanitize.array(v, maxKeypoints)
	local out = {}
	for _, kp in items do
		table.insert(out, {
			Sanitize.number(kp[1], 0, 0, 1),
			Sanitize.number(kp[2], 255, 0, 255),
			Sanitize.number(kp[3], 255, 0, 255),
			Sanitize.number(kp[4], 255, 0, 255),
		})
	end
	return Sanitize.fixSequence(out, default)
end

-- NumberSequence: { {t, value, envelope}, ... }.
function Sanitize.numSeq(v: any, default: { { number } }, maxKeypoints: number, min: number?, max: number?): { { number } }
	local items = Sanitize.array(v, maxKeypoints)
	local out = {}
	for _, kp in items do
		local value = Sanitize.number(kp[2], 0, min, max)
		local envelope = Sanitize.number(kp[3], 0, 0, max)
		table.insert(out, { Sanitize.number(kp[1], 0, 0, 1), value, envelope })
	end
	return Sanitize.fixSequence(out, default)
end

-- Roblox requires sequences to start at t=0, end at t=1 and be sorted.
function Sanitize.fixSequence(seq: { { number } }, default: { { number } }): { { number } }
	if #seq < 2 then
		local copy = {}
		for i, kp in default do
			copy[i] = table.clone(kp)
		end
		return copy
	end
	table.sort(seq, function(a, b)
		return a[1] < b[1]
	end)
	seq[1][1] = 0
	seq[#seq][1] = 1
	-- drop duplicate times (Roblox errors on them for ColorSequence)
	local out = { seq[1] }
	for i = 2, #seq do
		if seq[i][1] > out[#out][1] or i == #seq then
			table.insert(out, seq[i])
		end
	end
	if out[#out][1] ~= 1 then
		out[#out][1] = 1
	end
	if #out >= 2 and out[#out - 1][1] >= 1 then
		table.remove(out, #out - 1)
	end
	return out
end

-- NumberRange: {min, max} with min <= max.
function Sanitize.range(v: any, default: { number }, min: number?, max: number?): { number }
	local r = Sanitize.vector(v, 2, default, min, max)
	if r[1] > r[2] then
		r[1], r[2] = r[2], r[1]
	end
	return r
end

return Sanitize
