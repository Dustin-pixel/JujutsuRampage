--!strict
-- Converts between the plain-table encoding used in codes / DataStores and
-- real Roblox datatypes. Inputs here are assumed to be validated already.

local VfxSerialize = {}

function VfxSerialize.assetUrl(id: string): string
	if id == nil or id == "" then
		return ""
	end
	return "rbxassetid://" .. id
end

function VfxSerialize.assetIdFromUrl(url: string): string
	return string.match(url, "(%d+)") or ""
end

-- plain -> Roblox ---------------------------------------------------------

function VfxSerialize.toColor3(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function VfxSerialize.toVector3(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

function VfxSerialize.toVector2(v: { number }): Vector2
	return Vector2.new(v[1], v[2])
end

function VfxSerialize.toNumberRange(r: { number }): NumberRange
	return NumberRange.new(r[1], r[2])
end

function VfxSerialize.toColorSequence(seq: { { number } }): ColorSequence
	local kps = table.create(#seq)
	for i, kp in seq do
		kps[i] = ColorSequenceKeypoint.new(kp[1], Color3.fromRGB(kp[2], kp[3], kp[4]))
	end
	return ColorSequence.new(kps)
end

function VfxSerialize.toNumberSequence(seq: { { number } }): NumberSequence
	local kps = table.create(#seq)
	for i, kp in seq do
		-- envelope can't exceed value distance from 0 in some contexts; clamp softly
		kps[i] = NumberSequenceKeypoint.new(kp[1], kp[2], math.min(kp[3] or 0, math.abs(kp[2])))
	end
	return NumberSequence.new(kps)
end

-- Roblox -> plain ---------------------------------------------------------

local function round(n: number, places: number?): number
	local m = 10 ^ (places or 3)
	return math.floor(n * m + 0.5) / m
end

function VfxSerialize.fromColor3(c: Color3): { number }
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

function VfxSerialize.fromVector3(v: Vector3): { number }
	return { round(v.X), round(v.Y), round(v.Z) }
end

function VfxSerialize.fromVector2(v: Vector2): { number }
	return { round(v.X), round(v.Y) }
end

function VfxSerialize.fromNumberRange(r: NumberRange): { number }
	return { round(r.Min), round(r.Max) }
end

function VfxSerialize.fromColorSequence(s: ColorSequence): { { number } }
	local out = {}
	for _, kp in s.Keypoints do
		local c = VfxSerialize.fromColor3(kp.Value)
		table.insert(out, { round(kp.Time), c[1], c[2], c[3] })
	end
	return out
end

function VfxSerialize.fromNumberSequence(s: NumberSequence): { { number } }
	local out = {}
	for _, kp in s.Keypoints do
		table.insert(out, { round(kp.Time), round(kp.Value), round(kp.Envelope) })
	end
	return out
end

-- Converts a validated prop value into the Roblox value for its type.
function VfxSerialize.decodeProp(propType: string, value: any): any
	if propType == "color" then
		return VfxSerialize.toColor3(value)
	elseif propType == "colorSeq" then
		return VfxSerialize.toColorSequence(value)
	elseif propType == "numSeq" then
		return VfxSerialize.toNumberSequence(value)
	elseif propType == "range" then
		return VfxSerialize.toNumberRange(value)
	elseif propType == "vector3" then
		return VfxSerialize.toVector3(value)
	elseif propType == "vector2" then
		return VfxSerialize.toVector2(value)
	elseif propType == "asset" then
		return VfxSerialize.assetUrl(value)
	end
	return value
end

-- Converts a Roblox value into the plain encoding for its type.
function VfxSerialize.encodeProp(propType: string, value: any): any
	if propType == "color" then
		return VfxSerialize.fromColor3(value)
	elseif propType == "colorSeq" then
		return VfxSerialize.fromColorSequence(value)
	elseif propType == "numSeq" then
		return VfxSerialize.fromNumberSequence(value)
	elseif propType == "range" then
		return VfxSerialize.fromNumberRange(value)
	elseif propType == "vector3" then
		return VfxSerialize.fromVector3(value)
	elseif propType == "vector2" then
		return VfxSerialize.fromVector2(value)
	elseif propType == "asset" then
		return VfxSerialize.assetIdFromUrl(value)
	elseif propType == "enum" and typeof(value) == "EnumItem" then
		return value.Name
	elseif propType == "number" then
		return round(value)
	end
	return value
end

return VfxSerialize
