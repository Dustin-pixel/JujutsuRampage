--!strict
-- What a VFX effect may contain. Same idea as Blocks.luau: the editor, the
-- validator, the Studio exporter and the builder all read from this table.
--
-- An effect definition:
--   {
--     name = "Black Flash",
--     layers = {
--       { kind = "Emitter", name = "Sparks", offset = {0,0,0}, props = { Rate = 0, EmitCount = 40, ... } },
--       { kind = "Mesh", name = "Ring", props = { MeshId = "123", Scale = {...}, ... } },
--       ...
--     }
--   }
--
-- Property value encodings (see VfxSerialize):
--   number  -> number
--   color   -> {r,g,b} 0-255
--   colorSeq-> { {t, r,g,b}, ... }
--   numSeq  -> { {t, value, envelope}, ... }
--   range   -> {min, max}
--   vector3 -> {x,y,z}
--   vector2 -> {x,y}
--   asset   -> numeric string ("" = none)

local Config = require(script.Parent.Parent.Config)
local Util = require(script.Parent.Parent.Util)

export type PropType = "number" | "int" | "bool" | "color" | "colorSeq" | "numSeq" | "range" | "vector3" | "vector2" | "asset" | "enum"

export type PropDef = {
	key: string,
	type: PropType,
	default: any,
	min: number?,
	max: number?,
	options: { string }?,
	label: string?,
}

local V = Config.Vfx

local function p(key: string, t: PropType, default: any, min: number?, max: number?, options: { string }?): PropDef
	return { key = key, type = t, default = default, min = min, max = max, options = options }
end

-- Layer-level settings that apply to every kind.
local COMMON: { PropDef } = {
	p("Delay", "number", 0, 0, V.MaxDuration),
}

local KINDS: { [string]: { PropDef } } = {
	Emitter = {
		p("Texture", "asset", "", nil, nil),
		p("Color", "colorSeq", { { 0, 255, 255, 255 }, { 1, 255, 255, 255 } }),
		p("Size", "numSeq", { { 0, 1, 0 }, { 1, 0, 0 } }, 0, V.MaxSize),
		p("Transparency", "numSeq", { { 0, 0, 0 }, { 1, 1, 0 } }, 0, 1),
		p("Squash", "numSeq", { { 0, 0, 0 }, { 1, 0, 0 } }, -3, 3),
		p("Lifetime", "range", { 0.5, 1 }, 0, V.MaxLifetime),
		p("Speed", "range", { 5, 10 }, -200, 200),
		p("Rotation", "range", { 0, 0 }, -360, 360),
		p("RotSpeed", "range", { 0, 0 }, -1000, 1000),
		p("SpreadAngle", "vector2", { 30, 30 }, -360, 360),
		p("Acceleration", "vector3", { 0, 0, 0 }, -200, 200),
		p("Drag", "number", 0, 0, 20),
		p("Rate", "number", 0, 0, V.MaxRatePerEmitter),
		p("EmitCount", "int", 20, 0, V.MaxEmitBurst), -- burst fired when the effect plays
		p("LightEmission", "number", 1, 0, 1),
		p("LightInfluence", "number", 0, 0, 1),
		p("Brightness", "number", 1, 0, 10),
		p("ZOffset", "number", 0, -10, 10),
		p("LockedToPart", "bool", false),
		p("Orientation", "enum", "FacingCamera", nil, nil, { "FacingCamera", "FacingCameraWorldUp", "VelocityParallel", "VelocityPerpendicular" }),
		p("Shape", "enum", "Box", nil, nil, { "Box", "Sphere", "Cylinder", "Disc" }),
		p("ShapeStyle", "enum", "Volume", nil, nil, { "Volume", "Surface" }),
		p("ShapeInOut", "enum", "Outward", nil, nil, { "Outward", "Inward", "InAndOut" }),
		p("FlipbookLayout", "enum", "None", nil, nil, { "None", "Grid2x2", "Grid4x4", "Grid8x8" }),
		p("FlipbookMode", "enum", "Loop", nil, nil, { "Loop", "OneShot", "PingPong", "Random" }),
		p("FlipbookFramerate", "range", { 1, 1 }, 0, 60),
		p("EmitterSize", "vector3", { 1, 1, 1 }, 0.05, 30), -- size of the emitting volume
	},
	Mesh = {
		p("Shape", "enum", "FileMesh", nil, nil, { "FileMesh", "Sphere", "Brick", "Cylinder", "Wedge" }), -- built-in shapes need no asset
		p("MeshId", "asset", "", nil, nil),
		p("TextureId", "asset", "", nil, nil),
		p("Color", "color", { 255, 255, 255 }),
		p("Material", "enum", "Neon", nil, nil, { "Neon", "ForceField", "Glass", "SmoothPlastic", "Plastic" }),
		p("StartScale", "vector3", { 1, 1, 1 }, 0, V.MaxSize),
		p("EndScale", "vector3", { 3, 3, 3 }, 0, V.MaxSize),
		p("StartTransparency", "number", 0, 0, 1),
		p("EndTransparency", "number", 1, 0, 1),
		p("Rotation", "vector3", { 0, 0, 0 }, -360, 360), -- starting orientation (deg)
		p("Spin", "vector3", { 0, 0, 0 }, -1440, 1440), -- deg/sec
		p("Duration", "number", 0.5, 0.05, V.MaxDuration),
		p("Easing", "enum", "Quad", nil, nil, { "Linear", "Quad", "Cubic", "Quart", "Exponential", "Back", "Sine" }),
	},
	Beam = {
		p("Texture", "asset", "", nil, nil),
		p("Color", "colorSeq", { { 0, 255, 255, 255 }, { 1, 255, 255, 255 } }),
		p("Transparency", "numSeq", { { 0, 0, 0 }, { 1, 0, 0 } }, 0, 1),
		p("Width0", "number", 1, 0, V.MaxSize),
		p("Width1", "number", 1, 0, V.MaxSize),
		p("Length", "number", 10, 0, 100), -- beam goes from layer offset forward this far
		p("CurveSize0", "number", 0, -50, 50),
		p("CurveSize1", "number", 0, -50, 50),
		p("TextureSpeed", "number", 1, -20, 20),
		p("TextureLength", "number", 1, 0.05, 20),
		p("LightEmission", "number", 1, 0, 1),
		p("Segments", "int", 10, 1, 50),
		p("Duration", "number", 0.5, 0.05, V.MaxDuration),
	},
	Light = {
		p("Color", "color", { 255, 255, 255 }),
		p("Brightness", "number", 3, 0, 20),
		p("Range", "number", 12, 0, 60),
		p("Duration", "number", 0.3, 0.05, V.MaxDuration),
	},
}

local VfxSchema = {
	Kinds = KINDS,
	KindOrder = { "Emitter", "Mesh", "Beam", "Light" },
	Common = COMMON,
	PropsByKind = {} :: { [string]: { [string]: PropDef } },
}

for kind, props in KINDS do
	local map = {}
	for _, def in props do
		map[def.key] = def
	end
	for _, def in COMMON do
		map[def.key] = def
	end
	VfxSchema.PropsByKind[kind] = map
end

function VfxSchema.newLayer(kind: string): any
	local props = {}
	for _, def in KINDS[kind] do
		props[def.key] = Util.deepCopy(def.default)
	end
	for _, def in COMMON do
		props[def.key] = def.default
	end
	return { kind = kind, name = kind, offset = { 0, 0, 0 }, props = props }
end

function VfxSchema.newEffect(name: string?): any
	return { name = name or "New Effect", layers = { VfxSchema.newLayer("Emitter") } }
end

return VfxSchema
