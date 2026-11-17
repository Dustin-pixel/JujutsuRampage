--!strict
local Util = {}

function Util.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[k] = Util.deepCopy(v)
	end
	return out :: any
end

function Util.newId(): string
	-- short random id for effects in a library
	local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	local out = table.create(8)
	for i = 1, 8 do
		local n = math.random(1, #chars)
		out[i] = string.sub(chars, n, n)
	end
	return table.concat(out)
end

return Util
