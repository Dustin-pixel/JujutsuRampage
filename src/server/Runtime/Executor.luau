--!strict
-- Runs validated moves. A fighter (player character or NPC) has a "loadout":
-- the equipped moveset, per-move cooldowns, fighter variables and charge state.
--
-- Safety nets on top of the validator's budgets:
--   * every move gets a hard deadline (Budget.MaxDuration + 2s); background
--     blocks (Domain) get their own deadline from their duration,
--   * a move stops when its caster is stunned (unless armored) or dies,
--   * one move at a time per fighter (Passives and Domains excepted).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local CombatService = require(script.Parent.Parent.CombatService)
local VfxService = require(script.Parent.Parent.VfxService)
local Actions = require(script.Parent.Actions)

local Executor = {}

type Loadout = {
	model: Model,
	ownerKey: string,
	moveset: any,
	cooldowns: { [number]: number },
	busyUntil: number,
	running: { [any]: boolean }, -- shared tables of active moves
	vars: { [string]: number }, -- fighter-scope variables
	charging: { slot: number, start: number }?,
	passiveThread: thread?,
	onCooldown: ((slot: number, seconds: number) -> ())?,
}

local loadouts: { [Model]: Loadout } = {}
local CHARGE_KEY = {} -- speed modifier key

local function runBlocks(ctx: any, blocks: { any }?)
	if not blocks then
		return
	end
	for _, block in blocks do
		local shared = ctx.shared
		if shared.stopped or os.clock() > shared.deadline then
			return
		end
		if not CombatService.isAlive(ctx.caster) then
			shared.stopped = true
			return
		end
		if not ctx.ignoreStun and CombatService.isStunned(ctx.caster) and not CombatService.hasArmor(ctx.caster) then
			shared.stopped = true
			return
		end
		local handler = Actions[block.type]
		if handler then
			local ok, err = pcall(handler, ctx, block)
			if not ok then
				warn(`[Executor] block {block.type} failed: {err}`)
				shared.stopped = true
				return
			end
		end
	end
end

local function setCooldown(loadout: Loadout, slot: number, seconds: number)
	local untilTime = os.clock() + seconds
	if untilTime > (loadout.cooldowns[slot] or 0) then
		loadout.cooldowns[slot] = untilTime
		if loadout.onCooldown then
			loadout.onCooldown(slot, seconds)
		end
	end
end

-- Domain burnout: every move goes on cooldown for at least `seconds`.
local function burnout(loadout: Loadout, seconds: number)
	for slot in loadout.moveset.moves do
		setCooldown(loadout, slot, seconds)
	end
end

local function startMove(loadout: Loadout, slot: number, move: any, target: Model?, aim: Vector3?, charge: number?)
	local root = CombatService.root(loadout.model)
	if not root then
		return
	end
	local shared = {
		anyHit = false,
		stopped = false,
		deadline = os.clock() + Config.Budget.MaxDuration + 2,
	}
	local ctx = {
		caster = loadout.model,
		root = root,
		ownerKey = loadout.ownerKey,
		target = target,
		aim = aim,
		charge = charge or 1,
		shared = shared,
		vars = {}, -- move-scope variables
		fighterVars = loadout.vars,
		runBlocks = runBlocks,
		burnout = function(seconds: number)
			if loadouts[loadout.model] == loadout then
				burnout(loadout, seconds)
			end
		end,
		-- counters fire as a reaction, so don't cancel them on a stale stun
		ignoreStun = move.trigger.type == "Counter",
	}
	setCooldown(loadout, slot, move.cooldown)
	loadout.running[shared] = true
	local isPassive = move.trigger.type == "Passive"
	if not isPassive then
		loadout.busyUntil = shared.deadline
	end
	task.spawn(function()
		runBlocks(ctx, move.blocks)
		loadout.running[shared] = nil
		if not isPassive then
			loadout.busyUntil = 0
		end
	end)
end

local function ready(loadout: Loadout, slot: number): boolean
	return (loadout.cooldowns[slot] or 0) <= os.clock()
end

local function stopCharging(loadout: Loadout)
	if loadout.charging then
		loadout.charging = nil
		CombatService.setSpeedMod(loadout.model, CHARGE_KEY, nil)
	end
end

function Executor.equip(model: Model, moveset: any?, onCooldown: ((slot: number, seconds: number) -> ())?)
	Executor.unequip(model)
	if not moveset then
		return
	end
	local loadout: Loadout = {
		model = model,
		ownerKey = VfxService.ownerKey(model),
		moveset = moveset,
		cooldowns = {},
		busyUntil = 0,
		running = {},
		vars = {},
		charging = nil,
		onCooldown = onCooldown,
	}
	loadouts[model] = loadout
	VfxService.setLibrary(loadout.ownerKey, moveset.vfx or {})

	-- Passives tick on their own.
	local hasPassive = false
	for _, move in moveset.moves do
		if move.trigger.type == "Passive" then
			hasPassive = true
		end
	end
	if hasPassive then
		loadout.passiveThread = task.spawn(function()
			while loadouts[model] == loadout do
				task.wait(1)
				if CombatService.isAlive(model) then
					for slot, move in moveset.moves do
						if move.trigger.type == "Passive" and ready(loadout, slot) then
							startMove(loadout, slot, move, nil, nil, nil)
							setCooldown(loadout, slot, math.max(move.cooldown, move.trigger.fields.interval))
						end
					end
				end
			end
		end)
	end
end

function Executor.unequip(model: Model)
	local loadout = loadouts[model]
	if not loadout then
		return
	end
	stopCharging(loadout)
	loadouts[model] = nil
	for shared in loadout.running do
		shared.stopped = true
	end
	VfxService.clear(loadout.ownerKey)
end

-- Player pressed ("down") or released ("up") the key for `slot`.
function Executor.use(model: Model, slot: number, aim: Vector3?, phase: string?)
	local loadout = loadouts[model]
	if not loadout then
		return
	end
	local move = loadout.moveset.moves[slot]
	if not move then
		return
	end
	local trigger = move.trigger.type
	phase = if phase == "up" then "up" else "down"

	if trigger == "Charge" then
		if phase == "down" then
			if ready(loadout, slot) and os.clock() >= loadout.busyUntil and not CombatService.isStunned(model) and not loadout.charging then
				loadout.charging = { slot = slot, start = os.clock() }
				CombatService.setSpeedMod(model, CHARGE_KEY, Config.Charge.SpeedWhileCharging)
			end
		else
			local charging = loadout.charging
			if charging and charging.slot == slot then
				stopCharging(loadout)
				if CombatService.isStunned(model) then
					return -- charge was interrupted
				end
				-- The server measures the hold time itself; the client can't fake charge.
				local charge = math.clamp((os.clock() - charging.start) / move.trigger.fields.maxCharge, 0, 1)
				startMove(loadout, slot, move, nil, aim, charge)
			end
		end
		return
	end

	if phase ~= "down" or not ready(loadout, slot) then
		return
	end
	if os.clock() < loadout.busyUntil or CombatService.isStunned(model) or loadout.charging then
		return
	end
	if trigger == "Press" then
		startMove(loadout, slot, move, nil, aim, nil)
	elseif trigger == "Counter" then
		setCooldown(loadout, slot, move.cooldown)
		CombatService.openCounter(model, move.trigger.fields.window, function(attacker)
			if loadouts[model] == loadout then
				startMove(loadout, slot, move, attacker, nil, nil)
			end
		end)
	end
	-- ComboFinisher and Passive moves are not pressed.
end

function Executor.isBusy(model: Model): boolean
	local loadout = loadouts[model]
	return loadout ~= nil and (os.clock() < loadout.busyUntil or loadout.charging ~= nil)
end

CombatService.onComboFinished = function(attacker, target)
	local loadout = loadouts[attacker]
	if not loadout then
		return
	end
	for slot, move in loadout.moveset.moves do
		if move.trigger.type == "ComboFinisher" and ready(loadout, slot) then
			startMove(loadout, slot, move, target, nil, nil)
			return
		end
	end
end

return Executor
