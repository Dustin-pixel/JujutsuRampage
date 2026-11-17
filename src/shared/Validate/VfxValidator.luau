--!strict
-- Turns untrusted data (an imported code, a client save request) into a clean
-- VFX effect definition that only contains whitelisted layer kinds and
-- properties, all clamped to safe ranges.

local Config = require(script.Parent.Parent.Config)
local VfxSchema = require(script.Parent.Parent.Vfx.VfxSchema)
local Sanitize = require(script.Parent.Sanitize)

local VfxValidator = {}

local MAX_KP = Config.Vfx.MaxSequenceKeypoints

local function sanitizeProp(def: VfxSchema.PropDef, v: any): any
	local t = def.type
	if t == "number" then
		return Sanitize.number(v, def.default, def.min, def.max)
	elseif t == "int" then
		return Sanitize.int(v, def.default, def.min, def.max)
	elseif t == "bool" then
		return Sanitize.bool(v, def.default)
	elseif t == "enum" then
		return Sanitize.enum(v, def.options :: { string }, def.default)
	elseif t == "asset" then
		return Sanitize.asset(v)
	elseif t == "color" then
		return Sanitize.color(v, def.default)
	elseif t == "colorSeq" then
		return Sanitize.colorSeq(v, def.default, MAX_KP)
	elseif t == "numSeq" then
		return Sanitize.numSeq(v, def.default, MAX_KP, def.min, def.max)
	elseif t == "range" then
		return Sanitize.range(v, def.default, def.min, def.max)
	elseif t == "vector3" then
		return Sanitize.vector(v, 3, def.default, def.min, def.max)
	elseif t == "vector2" then
		return Sanitize.vector(v, 2, def.default, def.min, def.max)
	end
	return def.default
end

function VfxValidator.layer(raw: any): any?
	if type(raw) ~= "table" or type(raw.kind) ~= "string" then
		return nil
	end
	local defs = VfxSchema.Kinds[raw.kind]
	if not defs then
		return nil
	end
	local rawProps = if type(raw.props) == "table" then raw.props else {}
	local props = {}
	for _, def in defs do
		props[def.key] = sanitizeProp(def, rawProps[def.key])
	end
	for _, def in VfxSchema.Common do
		props[def.key] = sanitizeProp(def, rawProps[def.key])
	end
	return {
		kind = raw.kind,
		name = Sanitize.text(raw.name, Config.Vfx.MaxNameLength, raw.kind),
		offset = Sanitize.vector(raw.offset, 3, { 0, 0, 0 }, -20, 20),
		props = props,
	}
end

-- Returns a clean effect, or nil + reason if nothing usable is left.
function VfxValidator.effect(raw: any): (any?, string?)
	if type(raw) ~= "table" then
		return nil, "Effect data is missing."
	end
	local layers = {}
	for _, rawLayer in Sanitize.array(raw.layers, Config.Vfx.MaxLayers) do
		local layer = VfxValidator.layer(rawLayer)
		if layer then
			table.insert(layers, layer)
		end
	end
	if #layers == 0 then
		return nil, "Effect has no valid layers."
	end
	return {
		name = Sanitize.text(raw.name, Config.Vfx.MaxNameLength, "Effect"),
		layers = layers,
	}, nil
end

-- A library is a map of id -> effect.
function VfxValidator.library(raw: any, maxCount: number?): { [string]: any }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	local limit = maxCount or Config.Vfx.MaxLibrarySize
	local count = 0
	for id, effect in raw do
		if count >= limit then
			break
		end
		local cleanId = Sanitize.id(id)
		if cleanId ~= "" then
			local clean = VfxValidator.effect(effect)
			if clean then
				out[cleanId] = clean
				count += 1
			end
		end
	end
	return out
end

return VfxValidator
