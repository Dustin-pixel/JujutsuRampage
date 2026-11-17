--!strict
-- Turns untrusted data into a clean moveset and checks its power budget.
--
-- Used in two places:
--   * the server, on every save / import / equip (authoritative), and
--   * the builder UI, for live "this move is over budget" feedback.
--
-- Moveset shape:
--   {
--     name = "Cursed Speech", description = "...", color = {r,g,b},
--     moves = {
--       { name = "Blast Away", cooldown = 6, trigger = { type = "Press", fields = {} }, blocks = { ... } },
--     },
--     vfx = { [id] = effect },   -- effects referenced by PlayVfx / Projectile (embedded so one code shares everything)
--   }

local Config = require(script.Parent.Parent.Config)
local Blocks = require(script.Parent.Parent.Schema.Blocks)
local Triggers = require(script.Parent.Parent.Schema.Triggers)
local Sanitize = require(script.Parent.Sanitize)
local VfxValidator = require(script.Parent.VfxValidator)

local M = Config.Moveset
local B = Config.Budget

local MovesetValidator = {}

export type Totals = {
	damage: number,
	duration: number,
	hitboxes: number,
	projectiles: number,
	heal: number,
}

export type MoveReport = {
	totals: Totals,
	errors: { string },
	warnings: { string },
	minCooldown: number,
}

export type Result = {
	ok: boolean,
	value: any?,
	errors: { string }, -- fatal: the moveset cannot be saved/equipped
	warnings: { string }, -- informational: something was clamped or dropped
	reports: { MoveReport },
}

-- Targets: how many times blocks inside a target slot can run per execution.
local function slotMultiplier(def: Blocks.BlockDef, fields: any, slot: string): number
	if def.id == "Hitbox" and slot == "onHit" then
		return fields.maxTargets
	elseif def.id == "Projectile" and slot == "onHit" then
		return if fields.pierce then 5 else 1
	end
	return 1
end

local function sanitizeField(field: Blocks.Field, v: any): any
	local t = field.type
	if t == "number" then
		return Sanitize.number(v, field.default, field.min, field.max)
	elseif t == "int" then
		return Sanitize.int(v, field.default, field.min, field.max)
	elseif t == "bool" then
		return Sanitize.bool(v, field.default)
	elseif t == "enum" then
		return Sanitize.enum(v, field.options :: { string }, field.default)
	elseif t == "vector3" then
		return Sanitize.vector(v, 3, field.default, field.min, field.max)
	elseif t == "asset" then
		return Sanitize.asset(v)
	elseif t == "vfx" then
		return Sanitize.id(v)
	end
	return field.default
end

type Ctx = {
	count: number,
	report: MoveReport,
	vfxIds: { [string]: boolean },
	moveName: string,
}

local function addTotals(totals: Totals, budget: Blocks.Budget, mult: number, damageMult: number)
	totals.damage += (budget.damage or 0) * damageMult
	totals.duration += (budget.duration or 0) * mult
	totals.hitboxes += (budget.hitboxes or 0) * mult
	totals.projectiles += (budget.projectiles or 0) * mult
	totals.heal += (budget.heal or 0) * mult
end

-- Returns a clean list of blocks. `mult` multiplies counts/durations;
-- `damageMult` multiplies damage (only Repeat affects per-target damage).
local function sanitizeBlocks(raw: any, ctx: Ctx, depth: number, hasTarget: boolean, mult: number, damageMult: number): { any }
	local out = {}
	for _, rawBlock in Sanitize.array(raw, M.MaxBlocksPerMove) do
		if ctx.count >= M.MaxBlocksPerMove then
			table.insert(ctx.report.warnings, `{ctx.moveName}: block limit ({M.MaxBlocksPerMove}) reached, extra blocks removed.`)
			break
		end
		local def = Blocks.ById[rawBlock.type]
		if not def then
			table.insert(ctx.report.warnings, `{ctx.moveName}: unknown block "{tostring(rawBlock.type)}" removed.`)
			continue
		end
		if def.requiresTarget and not hasTarget then
			table.insert(
				ctx.report.errors,
				`{ctx.moveName}: "{def.label}" needs a target. Put it inside a Hitbox/Projectile "onHit", or use a Counter / Combo Finisher trigger.`
			)
		end
		ctx.count += 1

		local rawFields = if type(rawBlock.fields) == "table" then rawBlock.fields else {}
		local fields = {}
		for _, field in def.fields do
			fields[field.key] = sanitizeField(field, rawFields[field.key])
			if field.type == "vfx" and fields[field.key] ~= "" then
				ctx.vfxIds[fields[field.key]] = true
			end
		end

		if def.budget then
			addTotals(ctx.report.totals, def.budget(fields), mult, damageMult)
		end

		local block: any = { type = def.id, fields = fields }
		if def.slots then
			local rawChildren = if type(rawBlock.children) == "table" then rawBlock.children else {}
			block.children = {}
			local childMult = if def.childMultiplier then def.childMultiplier(fields) else 1
			for _, slot in def.slots do
				if depth >= M.MaxNestingDepth then
					block.children[slot] = {}
					if type(rawChildren[slot]) == "table" and #rawChildren[slot] > 0 then
						table.insert(ctx.report.warnings, `{ctx.moveName}: blocks nested deeper than {M.MaxNestingDepth} levels were removed.`)
					end
				else
					local slotTarget = hasTarget or (def.targetSlots ~= nil and def.targetSlots[slot] == true)
					local sm = slotMultiplier(def, fields, slot)
					block.children[slot] = sanitizeBlocks(rawChildren[slot], ctx, depth + 1, slotTarget, mult * childMult * sm, damageMult * childMult)
				end
			end
		end
		table.insert(out, block)
	end
	return out
end

local function checkBudget(report: MoveReport, name: string)
	local t = report.totals
	local function over(what: string, value: number, limit: number)
		table.insert(report.errors, `{name}: {what} is {math.floor(value * 10 + 0.5) / 10}, the limit is {limit}.`)
	end
	if t.damage > B.MaxDamage then
		over("total damage per target", t.damage, B.MaxDamage)
	end
	if t.duration > B.MaxDuration then
		over("total duration (s)", t.duration, B.MaxDuration)
	end
	if t.hitboxes > B.MaxHitboxes then
		over("hitbox count", t.hitboxes, B.MaxHitboxes)
	end
	if t.projectiles > B.MaxProjectiles then
		over("projectile count", t.projectiles, B.MaxProjectiles)
	end
	if t.heal > B.MaxHeal then
		over("total healing", t.heal, B.MaxHeal)
	end
	report.minCooldown = math.max(B.MinCooldown, t.damage / B.DamagePerCooldownSecond, t.heal / 2)
end

function MovesetValidator.move(raw: any, index: number, vfxIds: { [string]: boolean }): (any, MoveReport)
	raw = if type(raw) == "table" then raw else {}
	local report: MoveReport = {
		totals = { damage = 0, duration = 0, hitboxes = 0, projectiles = 0, heal = 0 },
		errors = {},
		warnings = {},
		minCooldown = B.MinCooldown,
	}
	local name = Sanitize.text(raw.name, M.MaxNameLength, `Move {index}`)
	if name == "" then
		name = `Move {index}`
	end

	-- trigger
	local rawTrigger = if type(raw.trigger) == "table" then raw.trigger else {}
	local tdef = Triggers.ById[rawTrigger.type] or Triggers.ById.Press
	local tfieldsRaw = if type(rawTrigger.fields) == "table" then rawTrigger.fields else {}
	local tfields = {}
	for _, field in tdef.fields do
		tfields[field.key] = Sanitize.number(tfieldsRaw[field.key], field.default, field.min, field.max)
	end
	local rootHasTarget = tdef.id == "Counter" or tdef.id == "ComboFinisher"

	local ctx: Ctx = { count = 0, report = report, vfxIds = vfxIds, moveName = name }
	local blocks = sanitizeBlocks(raw.blocks, ctx, 1, rootHasTarget, 1, 1)
	checkBudget(report, name)

	local cooldown = Sanitize.number(raw.cooldown, report.minCooldown, 0, 120)
	if cooldown < report.minCooldown then
		table.insert(report.warnings, `{name}: cooldown raised to {math.ceil(report.minCooldown * 10) / 10}s to match its power.`)
		cooldown = math.ceil(report.minCooldown * 10) / 10
	end

	return {
		name = name,
		cooldown = cooldown,
		trigger = { type = tdef.id, fields = tfields },
		blocks = blocks,
	}, report
end

function MovesetValidator.moveset(raw: any): Result
	local result: Result = { ok = false, value = nil, errors = {}, warnings = {}, reports = {} }
	if type(raw) ~= "table" then
		table.insert(result.errors, "Moveset data is missing.")
		return result
	end

	local vfxIds: { [string]: boolean } = {}
	local moves = {}
	for i, rawMove in Sanitize.array(raw.moves, M.MaxMoves) do
		local move, report = MovesetValidator.move(rawMove, i, vfxIds)
		table.insert(moves, move)
		table.insert(result.reports, report)
		for _, e in report.errors do
			table.insert(result.errors, e)
		end
		for _, w in report.warnings do
			table.insert(result.warnings, w)
		end
	end

	-- Only keep embedded effects that are actually referenced.
	local vfx = {}
	local library = VfxValidator.library(raw.vfx, Config.Vfx.MaxLibrarySize)
	for id in vfxIds do
		if library[id] then
			vfx[id] = library[id]
		end
	end

	result.value = {
		name = Sanitize.text(raw.name, M.MaxNameLength, "Unnamed Technique"),
		description = Sanitize.text(raw.description, M.MaxDescriptionLength, ""),
		color = Sanitize.color(raw.color, { 120, 90, 255 }),
		moves = moves,
		vfx = vfx,
	}
	if result.value.name == "" then
		result.value.name = "Unnamed Technique"
	end
	result.ok = #result.errors == 0
	return result
end

return MovesetValidator
