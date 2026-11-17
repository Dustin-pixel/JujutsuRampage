--!strict
-- Global tuning and hard limits. Every limit here is enforced server-side by the
-- validators, so imported codes can never exceed them.

local Config = {}

Config.CodePrefix = "JJR"
Config.FormatVersion = 1
Config.MaxCodeLength = 60000 -- characters in a pasted code

Config.Moveset = {
	MaxMoves = 6, -- hotbar slots 1..6
	MaxBlocksPerMove = 40, -- counted recursively, including nested blocks
	MaxNestingDepth = 3,
	MaxNameLength = 32,
	MaxDescriptionLength = 200,
	MaxSlotsSaved = 5, -- saved techniques per player
}

-- Per-move budgets. Totals are computed statically from the block list
-- (Repeat multiplies its children), so an import cannot sneak past them.
Config.Budget = {
	MaxDamage = 60, -- sum of Damage over the whole move
	MaxDuration = 8, -- seconds of Wait/hitbox/dash time
	MaxHitboxes = 12,
	MaxProjectiles = 8,
	MaxHeal = 30,
	MinCooldown = 1, -- seconds; every move has at least this cooldown
	DamagePerCooldownSecond = 12, -- damage over this ratio forces a longer cooldown
}

Config.Combat = {
	MaxHealth = 100,
	MaxCursedEnergy = 100,
	CursedEnergyRegen = 6, -- per second
	BlockDamageMultiplier = 0.25,
	M1Damage = 4,
	M1Cooldown = 0.35,
	M1ComboLength = 4,
	MaxStun = 2.5,
	MaxKnockback = 120,
}

Config.Vfx = {
	MaxLayers = 16, -- emitters + meshes + beams + lights in one effect
	MaxRatePerEmitter = 200,
	MaxEmitBurst = 150,
	MaxLifetime = 5,
	MaxSize = 30,
	MaxDuration = 6, -- seconds an effect may live before cleanup
	MaxLibrarySize = 40, -- saved effects per player
	MaxNameLength = 32,
	MaxSequenceKeypoints = 8,
}

Config.RateLimit = {
	UseMove = 12, -- requests per second
	Save = 1 / 2, -- one save per 2 seconds
	Import = 1 / 2,
}

return Config
