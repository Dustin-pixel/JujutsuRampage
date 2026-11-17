--!strict
-- The block registry: the single source of truth for what a move can contain.
--
-- The builder UI renders its palette and inspectors from this table, the
-- validator clamps imported data against it, and the server runtime only
-- executes block types that appear here. To add a block:
--   1. add an entry below,
--   2. add a handler with the same id in src/server/Runtime/Actions.luau,
--   3. document it in docs/BLOCKS.md.
--
-- A block instance inside a moveset looks like:
--   { type = "Hitbox", fields = { size = {6,5,6}, ... }, children = { onHit = { ...blocks } } }

local Util = require(script.Parent.Parent.Util)

export type FieldType = "number" | "int" | "bool" | "enum" | "vector3" | "asset" | "vfx"

export type Field = {
	key: string,
	label: string,
	type: FieldType,
	default: any,
	min: number?,
	max: number?,
	step: number?,
	options: { string }?,
	hint: string?,
}

export type Budget = {
	damage: number?,
	duration: number?,
	hitboxes: number?,
	projectiles: number?,
	heal: number?,
}

export type BlockDef = {
	id: string,
	label: string,
	category: "Flow" | "Combat" | "Movement" | "Self" | "Visual",
	description: string,
	fields: { Field },
	-- Named child lists ("branches"). Repeat has "body", If has "then"/"else",
	-- Hitbox and Projectile have "onHit".
	slots: { string }?,
	-- Child slots that run with a hit target available.
	targetSlots: { [string]: boolean }?,
	-- The block needs a hit target (only valid somewhere inside an onHit slot).
	requiresTarget: boolean?,
	-- Static cost of one execution, used for budgets.
	budget: ((fields: { [string]: any }) -> Budget)?,
	-- Multiplies the cost of everything in its slots (Repeat).
	childMultiplier: ((fields: { [string]: any }) -> number)?,
	color: Color3?,
}

local function num(key: string, label: string, default: number, min: number, max: number, step: number?, hint: string?): Field
	return { key = key, label = label, type = "number", default = default, min = min, max = max, step = step or 0.05, hint = hint }
end
local function int(key: string, label: string, default: number, min: number, max: number): Field
	return { key = key, label = label, type = "int", default = default, min = min, max = max, step = 1 }
end
local function bool(key: string, label: string, default: boolean): Field
	return { key = key, label = label, type = "bool", default = default }
end
local function enum(key: string, label: string, options: { string }, default: string?): Field
	return { key = key, label = label, type = "enum", options = options, default = default or options[1] }
end
local function vec(key: string, label: string, default: { number }, min: number, max: number): Field
	return { key = key, label = label, type = "vector3", default = default, min = min, max = max, step = 0.25 }
end
local function asset(key: string, label: string, hint: string?): Field
	return { key = key, label = label, type = "asset", default = "", hint = hint }
end
local function vfx(key: string, label: string): Field
	return { key = key, label = label, type = "vfx", default = "" }
end

local CATEGORY_COLORS = {
	Flow = Color3.fromRGB(240, 180, 60),
	Combat = Color3.fromRGB(230, 70, 80),
	Movement = Color3.fromRGB(70, 170, 240),
	Self = Color3.fromRGB(90, 210, 130),
	Visual = Color3.fromRGB(170, 110, 240),
}

local DIRECTIONS = { "Forward", "Backward", "Left", "Right", "Up", "Down" }

local list: { BlockDef } = {
	-- ── Flow ──────────────────────────────────────────────────────────────
	{
		id = "Wait",
		label = "Wait",
		category = "Flow",
		description = "Pause before running the next block.",
		fields = { num("seconds", "Seconds", 0.2, 0, 3) },
		budget = function(f)
			return { duration = f.seconds }
		end,
	},
	{
		id = "Repeat",
		label = "Repeat",
		category = "Flow",
		description = "Run the blocks inside several times.",
		fields = { int("count", "Times", 3, 1, 10) },
		slots = { "body" },
		childMultiplier = function(f)
			return f.count
		end,
	},
	{
		id = "If",
		label = "If",
		category = "Flow",
		description = "Run 'then' when the condition is true, otherwise 'else'.",
		fields = {
			enum("condition", "Condition", { "AnyTargetHit", "HealthBelow", "EnergyAbove", "Chance", "Airborne", "TargetBlocking" }),
			num("value", "Value (% / CE)", 50, 0, 100, 1, "Used by HealthBelow (%), EnergyAbove (CE) and Chance (%)."),
		},
		slots = { "then", "else" },
	},
	{
		id = "Stop",
		label = "Stop Move",
		category = "Flow",
		description = "End the move immediately.",
		fields = {},
	},

	-- ── Combat ────────────────────────────────────────────────────────────
	{
		id = "Hitbox",
		label = "Hitbox",
		category = "Combat",
		description = "Check for enemies in an area in front of you. Blocks in 'onHit' run once per enemy hit.",
		fields = {
			enum("shape", "Shape", { "Box", "Sphere" }),
			vec("size", "Size", { 5, 5, 5 }, 0.5, 30),
			vec("offset", "Offset (from you)", { 0, 0, -3 }, -25, 25),
			num("duration", "Active time", 0, 0, 1, 0.05, "0 = single check. >0 keeps checking (each enemy hit once)."),
			int("maxTargets", "Max targets", 3, 1, 10),
		},
		slots = { "onHit" },
		targetSlots = { onHit = true },
		budget = function(f)
			return { hitboxes = 1, duration = f.duration }
		end,
	},
	{
		id = "Projectile",
		label = "Projectile",
		category = "Combat",
		description = "Fire a projectile forward. Blocks in 'onHit' run on whoever it hits.",
		fields = {
			num("speed", "Speed", 80, 10, 250, 1),
			num("range", "Range", 80, 5, 300, 1),
			num("radius", "Radius", 1.5, 0.25, 10, 0.25),
			bool("pierce", "Pierce", false),
			vec("offset", "Spawn offset", { 0, 0, -2 }, -10, 10),
			vfx("vfx", "Projectile VFX"),
		},
		slots = { "onHit" },
		targetSlots = { onHit = true },
		budget = function(f)
			return { projectiles = 1 }
		end,
	},
	{
		id = "Damage",
		label = "Damage",
		category = "Combat",
		description = "Damage the target.",
		requiresTarget = true,
		fields = {
			num("amount", "Amount", 8, 0, 30, 0.5),
			bool("guardBreak", "Breaks block", false),
			bool("ignoreArmor", "Ignore super armor", false),
		},
		budget = function(f)
			return { damage = f.amount }
		end,
	},
	{
		id = "Knockback",
		label = "Knockback",
		category = "Combat",
		description = "Push the target.",
		requiresTarget = true,
		fields = {
			enum("direction", "Direction", { "Away", "Toward", "Up", "Down", "Forward" }),
			num("force", "Force", 40, 0, 120, 1),
		},
	},
	{
		id = "Stun",
		label = "Stun",
		category = "Combat",
		description = "Stop the target from moving or attacking.",
		requiresTarget = true,
		fields = { num("seconds", "Seconds", 0.6, 0, 2.5) },
	},
	{
		id = "Grab",
		label = "Grab",
		category = "Combat",
		description = "Hold the target in front of you (target is stunned while held).",
		requiresTarget = true,
		fields = {
			num("seconds", "Seconds", 1, 0.1, 2.5),
			vec("offset", "Hold offset", { 0, 0, -3 }, -10, 10),
		},
		budget = function(f)
			return { duration = f.seconds }
		end,
	},

	-- ── Movement ──────────────────────────────────────────────────────────
	{
		id = "Dash",
		label = "Dash",
		category = "Movement",
		description = "Move quickly in a direction relative to where you face.",
		fields = {
			enum("direction", "Direction", DIRECTIONS),
			num("distance", "Distance", 20, 0, 60, 1),
			num("seconds", "Seconds", 0.2, 0.05, 1),
		},
		budget = function(f)
			return { duration = f.seconds }
		end,
	},
	{
		id = "FaceTarget",
		label = "Face Nearest Enemy",
		category = "Movement",
		description = "Turn toward the closest enemy within range.",
		fields = { num("range", "Range", 40, 1, 100, 1) },
	},
	{
		id = "Teleport",
		label = "Teleport",
		category = "Movement",
		description = "Blink to a spot. With a target, blink behind them.",
		fields = {
			enum("mode", "Mode", { "Forward", "BehindTarget" }),
			num("distance", "Distance", 15, 0, 40, 1),
		},
	},

	-- ── Self ──────────────────────────────────────────────────────────────
	{
		id = "CostEnergy",
		label = "Spend Cursed Energy",
		category = "Self",
		description = "Spend cursed energy. If you don't have enough, the move stops here.",
		fields = { num("amount", "Amount", 15, 0, 100, 1) },
	},
	{
		id = "Heal",
		label = "Heal",
		category = "Self",
		description = "Restore your own health (Reverse Cursed Technique).",
		fields = { num("amount", "Amount", 10, 0, 30, 0.5) },
		budget = function(f)
			return { heal = f.amount }
		end,
	},
	{
		id = "Armor",
		label = "Super Armor",
		category = "Self",
		description = "Can't be stunned or knocked back for a while (still take damage).",
		fields = { num("seconds", "Seconds", 0.5, 0, 2) },
	},
	{
		id = "SpeedBoost",
		label = "Speed Boost",
		category = "Self",
		description = "Change your walk speed for a while.",
		fields = {
			num("multiplier", "Multiplier", 1.5, 0.25, 2.5),
			num("seconds", "Seconds", 2, 0.1, 6),
		},
	},

	-- ── Visual / Audio ────────────────────────────────────────────────────
	{
		id = "PlayAnimation",
		label = "Play Animation",
		category = "Visual",
		description = "Play an animation on your character.",
		fields = {
			asset("animationId", "Animation ID", "rbxassetid number. Must be owned by the game's creator/group."),
			num("speed", "Speed", 1, 0.1, 3),
			bool("stopPrevious", "Stop other anims", true),
		},
	},
	{
		id = "PlayVfx",
		label = "Play VFX",
		category = "Visual",
		description = "Play one of your VFX effects.",
		fields = {
			vfx("vfx", "Effect"),
			enum("at", "Attach to", { "Self", "Target", "InFront" }),
			vec("offset", "Offset", { 0, 0, 0 }, -20, 20),
			num("seconds", "Lifetime", 1, 0.1, 6),
		},
	},
	{
		id = "PlaySound",
		label = "Play Sound",
		category = "Visual",
		description = "Play a sound at your character.",
		fields = {
			asset("soundId", "Sound ID"),
			num("volume", "Volume", 0.7, 0, 2),
			num("pitch", "Pitch", 1, 0.5, 2),
		},
	},
	{
		id = "CameraShake",
		label = "Camera Shake",
		category = "Visual",
		description = "Shake the camera of nearby players.",
		fields = {
			num("intensity", "Intensity", 0.5, 0, 2),
			num("seconds", "Seconds", 0.3, 0, 2),
			num("radius", "Radius", 40, 0, 150, 1),
		},
	},
}

local Blocks = {
	List = list,
	ById = {} :: { [string]: BlockDef },
	Categories = { "Flow", "Combat", "Movement", "Self", "Visual" },
	CategoryColors = CATEGORY_COLORS,
}

for _, def in list do
	def.color = CATEGORY_COLORS[def.category]
	Blocks.ById[def.id] = def
end

-- Builds a new block instance with default field values.
function Blocks.create(id: string): any
	local def = Blocks.ById[id]
	assert(def, "unknown block " .. id)
	local fields = {}
	for _, field in def.fields do
		fields[field.key] = Util.deepCopy(field.default)
	end
	local children = nil
	if def.slots then
		children = {}
		for _, slot in def.slots do
			children[slot] = {}
		end
	end
	return { type = id, fields = fields, children = children }
end

return Blocks
