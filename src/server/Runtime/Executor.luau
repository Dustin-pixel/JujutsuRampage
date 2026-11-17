--!strict
-- Runs validated moves. A fighter (player character or NPC) has a "loadout":
-- the equipped moveset plus per-move cooldowns.
--
-- Safety nets on top of the validator's budgets:
--   * every move gets a hard deadline (Budget.MaxDuration + 2s),
--   * a move stops when its caster is stunned (unless armored) or dies,
--   * one move at a time per fighter (Passives excepted).

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
	passiveThread: thread?,
	onCooldown: ((slot: number, seconds: number) -> ())?,
}

local loadouts: { [Model]: Loadout } = {}

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

local function startMove(loadout: Loadout, slot: number, move: any, target: Model?, aim: Vector3?)
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
		shared = shared,
		runBlocks = runBlocks,
		-- counters fire as a reaction, so don't cancel them on a stale stun
		ignoreStun = move.trigger.type == "Counter",
	}
	loadout.cooldowns[slot] = os.clock() + move.cooldown
	if loadout.onCooldown then
		loadout.onCooldown(slot, move.cooldown)
	end
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
							startMove(loadout, slot, move, nil, nil)
							loadout.cooldowns[slot] = os.clock() + math.max(move.cooldown, move.trigger.fields.interval)
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
	loadouts[model] = nil
	for shared in loadout.running do
		shared.stopped = true
	end
	VfxService.clear(loadout.ownerKey)
end

-- Player pressed the key for `slot`.
function Executor.use(model: Model, slot: number, aim: Vector3?)
	local loadout = loadouts[model]
	if not loadout then
		return
	end
	local move = loadout.moveset.moves[slot]
	if not move or not ready(loadout, slot) then
		return
	end
	if os.clock() < loadout.busyUntil or CombatService.isStunned(model) then
		return
	end
	local trigger = move.trigger.type
	if trigger == "Press" then
		startMove(loadout, slot, move, nil, aim)
	elseif trigger == "Counter" then
		loadout.cooldowns[slot] = os.clock() + move.cooldown
		if loadout.onCooldown then
			loadout.onCooldown(slot, move.cooldown)
		end
		CombatService.openCounter(model, move.trigger.fields.window, function(attacker)
			if loadouts[model] == loadout then
				startMove(loadout, slot, move, attacker, nil)
			end
		end)
	end
	-- ComboFinisher and Passive moves are not pressed.
end

function Executor.isBusy(model: Model): boolean
	local loadout = loadouts[model]
	return loadout ~= nil and os.clock() < loadout.busyUntil
end

CombatService.onComboFinished = function(attacker, target)
	local loadout = loadouts[attacker]
	if not loadout then
		return
	end
	for slot, move in loadout.moveset.moves do
		if move.trigger.type == "ComboFinisher" and ready(loadout, slot) then
			startMove(loadout, slot, move, target, nil)
			return
		end
	end
end

return Executor
