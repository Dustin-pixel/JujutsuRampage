--!strict
-- Server-authoritative combat state for every fighter (players and NPCs):
-- health, cursed energy, stun, super armor, blocking, counters and M1 combos.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local C = Config.Combat

local CombatService = {}

export type CounterWindow = {
	untilTime: number,
	onCountered: (attacker: Model) -> (),
}

export type State = {
	model: Model,
	energy: number,
	stunUntil: number,
	armorUntil: number,
	blocking: boolean,
	counter: CounterWindow?,
	combo: number,
	lastM1: number,
	speedMods: { [any]: number },
	baseWalkSpeed: number,
	baseJumpHeight: number,
	baseJumpPower: number,
}

local states: { [Model]: State } = {}

local function now(): number
	return os.clock()
end

function CombatService.getState(model: Model): State?
	return states[model]
end

function CombatService.register(model: Model): State
	local existing = states[model]
	if existing then
		return existing
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local state: State = {
		model = model,
		energy = C.MaxCursedEnergy,
		stunUntil = 0,
		armorUntil = 0,
		blocking = false,
		counter = nil,
		combo = 0,
		lastM1 = 0,
		speedMods = {},
		baseWalkSpeed = if humanoid then humanoid.WalkSpeed else 16,
		baseJumpHeight = if humanoid then humanoid.JumpHeight else 7.2,
		baseJumpPower = if humanoid then humanoid.JumpPower else 50,
	}
	states[model] = state
	if humanoid then
		humanoid.MaxHealth = C.MaxHealth
		humanoid.Health = C.MaxHealth
		humanoid.Died:Connect(function()
			states[model] = nil
		end)
	end
	model.Destroying:Connect(function()
		states[model] = nil
	end)
	return state
end

function CombatService.humanoid(model: Model): Humanoid?
	local h = model:FindFirstChildOfClass("Humanoid")
	if h and h.Health > 0 then
		return h
	end
	return nil
end

function CombatService.root(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function CombatService.isAlive(model: Model): boolean
	return CombatService.humanoid(model) ~= nil and states[model] ~= nil
end

function CombatService.isStunned(model: Model): boolean
	local s = states[model]
	return s ~= nil and s.stunUntil > now()
end

function CombatService.hasArmor(model: Model): boolean
	local s = states[model]
	return s ~= nil and s.armorUntil > now()
end

-- Speed changes are stored per source so overlapping effects combine sanely.
local function applySpeed(state: State)
	local humanoid = state.model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if state.stunUntil > now() then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
		return
	end
	local mult = 1
	for _, m in state.speedMods do
		mult *= m
	end
	if state.blocking then
		mult *= 0.4
	end
	humanoid.WalkSpeed = state.baseWalkSpeed * mult
	humanoid.JumpHeight = state.baseJumpHeight
	humanoid.JumpPower = state.baseJumpPower
end

function CombatService.setSpeedMod(model: Model, key: any, multiplier: number?)
	local s = states[model]
	if not s then
		return
	end
	s.speedMods[key] = multiplier
	applySpeed(s)
end

function CombatService.stun(model: Model, seconds: number)
	local s = states[model]
	if not s or seconds <= 0 or CombatService.hasArmor(model) then
		return
	end
	seconds = math.min(seconds, C.MaxStun)
	s.stunUntil = math.max(s.stunUntil, now() + seconds)
	s.blocking = false
	applySpeed(s)
	task.delay(seconds + 0.02, function()
		if states[model] == s then
			applySpeed(s)
		end
	end)
end

function CombatService.setArmor(model: Model, seconds: number)
	local s = states[model]
	if s then
		s.armorUntil = math.max(s.armorUntil, now() + seconds)
	end
end

function CombatService.setBlocking(model: Model, blocking: boolean)
	local s = states[model]
	if not s then
		return
	end
	s.blocking = blocking and not CombatService.isStunned(model)
	applySpeed(s)
end

function CombatService.openCounter(model: Model, seconds: number, onCountered: (attacker: Model) -> ())
	local s = states[model]
	if s then
		s.counter = { untilTime = now() + seconds, onCountered = onCountered }
	end
end

function CombatService.spendEnergy(model: Model, amount: number): boolean
	local s = states[model]
	if not s or s.energy < amount then
		return false
	end
	s.energy -= amount
	return true
end

function CombatService.heal(model: Model, amount: number)
	local h = CombatService.humanoid(model)
	if h then
		h.Health = math.min(h.MaxHealth, h.Health + amount)
	end
end

-- Is `target` facing `attacker` (so a block applies)?
local function isFacing(target: Model, attacker: Model): boolean
	local tr, ar = CombatService.root(target), CombatService.root(attacker)
	if not tr or not ar then
		return false
	end
	local toAttacker = (ar.Position - tr.Position) * Vector3.new(1, 0, 1)
	if toAttacker.Magnitude < 0.01 then
		return true
	end
	return tr.CFrame.LookVector:Dot(toAttacker.Unit) > 0.1
end

export type HitResult = "hit" | "blocked" | "countered" | "invalid"

export type DamageOptions = {
	guardBreak: boolean?,
	ignoreArmor: boolean?,
	unblockable: boolean?, -- domain sure-hit: ignores blocking and counters
}

function CombatService.damage(attacker: Model, target: Model, amount: number, opts: DamageOptions?): HitResult
	local ts = states[target]
	local h = CombatService.humanoid(target)
	if not ts or not h or target == attacker then
		return "invalid"
	end
	local o = opts or {}

	-- Counter window: cancel the hit and fire the counter move.
	local counter = ts.counter
	if counter and counter.untilTime > now() and not o.unblockable then
		ts.counter = nil
		task.spawn(counter.onCountered, attacker)
		return "countered"
	end

	if ts.blocking and not o.unblockable and isFacing(target, attacker) then
		if o.guardBreak then
			ts.blocking = false
			CombatService.stun(target, 1.2)
		else
			h:TakeDamage(amount * C.BlockDamageMultiplier)
			return "blocked"
		end
	end

	h:TakeDamage(amount)
	return "hit"
end

local function direction(attacker: Model, target: Model, mode: string): Vector3
	local ar, tr = CombatService.root(attacker), CombatService.root(target)
	if not ar or not tr then
		return Vector3.zero
	end
	local flat = (tr.Position - ar.Position) * Vector3.new(1, 0, 1)
	local away = if flat.Magnitude > 0.01 then flat.Unit else ar.CFrame.LookVector
	if mode == "Away" then
		return (away + Vector3.new(0, 0.25, 0)).Unit
	elseif mode == "Toward" then
		return -away
	elseif mode == "Up" then
		return Vector3.yAxis
	elseif mode == "Down" then
		return -Vector3.yAxis
	end
	return ar.CFrame.LookVector
end

-- Applies a short-lived LinearVelocity; this works even when the client owns
-- the target's physics, because the constraint replicates.
function CombatService.push(part: BasePart, velocity: Vector3, seconds: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "PushAttachment"
	attachment.Parent = part
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.MaxForce = math.huge
	lv.VectorVelocity = velocity
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = part
	Debris:AddItem(lv, seconds)
	Debris:AddItem(attachment, seconds)
end

function CombatService.knockback(attacker: Model, target: Model, mode: string, force: number)
	if CombatService.hasArmor(target) then
		return
	end
	local tr = CombatService.root(target)
	if not tr then
		return
	end
	force = math.min(force, C.MaxKnockback)
	CombatService.push(tr, direction(attacker, target, mode) * force, 0.18)
end

-- Returns living fighter models whose parts overlap the box/sphere.
function CombatService.query(attacker: Model, cframe: CFrame, size: Vector3, shape: string): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker }
	local parts = if shape == "Sphere"
		then workspace:GetPartBoundsInRadius(cframe.Position, math.max(size.X, size.Y, size.Z) / 2, params)
		else workspace:GetPartBoundsInBox(cframe, size, params)
	local seen: { [Model]: boolean } = {}
	local out = {}
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		while model and not model:FindFirstChildOfClass("Humanoid") do
			model = model:FindFirstAncestorOfClass("Model")
		end
		if model and not seen[model] and CombatService.isAlive(model) then
			seen[model] = true
			table.insert(out, model)
		end
	end
	return out
end

-- Nearest living enemy within range.
function CombatService.nearest(attacker: Model, range: number): Model?
	local ar = CombatService.root(attacker)
	if not ar then
		return nil
	end
	local best, bestDist = nil, range
	for model in states do
		if model ~= attacker and CombatService.isAlive(model) then
			local r = CombatService.root(model)
			if r then
				local d = (r.Position - ar.Position).Magnitude
				if d < bestDist then
					best, bestDist = model, d
				end
			end
		end
	end
	return best
end

-- M1s -----------------------------------------------------------------------

-- Called with the target when the final M1 of a combo lands.
CombatService.onComboFinished = nil :: ((attacker: Model, target: Model) -> ())?

function CombatService.m1(attacker: Model)
	local s = states[attacker]
	local root = CombatService.root(attacker)
	if not s or not root or CombatService.isStunned(attacker) or s.blocking then
		return
	end
	local t = now()
	if t - s.lastM1 < C.M1Cooldown then
		return
	end
	if t - s.lastM1 > 1.2 then
		s.combo = 0
	end
	s.lastM1 = t
	s.combo = (s.combo % C.M1ComboLength) + 1
	local isFinal = s.combo == C.M1ComboLength

	local hits = CombatService.query(attacker, root.CFrame * CFrame.new(0, 0, -3), Vector3.new(5, 5, 5), "Box")
	for _, target in hits do
		local result = CombatService.damage(attacker, target, C.M1Damage)
		if result == "hit" then
			if isFinal then
				CombatService.knockback(attacker, target, "Away", 45)
				CombatService.stun(target, 0.5)
				if CombatService.onComboFinished then
					CombatService.onComboFinished(attacker, target)
				end
			else
				CombatService.stun(target, 0.45)
			end
		end
	end
end

-- HUD / regen loop ------------------------------------------------------------

local combatState = Remotes.event("CombatState")
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	for _, s in states do
		s.energy = math.min(C.MaxCursedEnergy, s.energy + C.CursedEnergyRegen * dt)
	end
	accumulator += dt
	if accumulator >= 0.2 then
		accumulator = 0
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local s = character and states[character]
			if s then
				combatState:FireClient(player, {
					energy = math.floor(s.energy),
					maxEnergy = C.MaxCursedEnergy,
					stunned = s.stunUntil > now(),
					blocking = s.blocking,
				})
			end
		end
	end
end)

return CombatService
