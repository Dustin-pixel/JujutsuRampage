--!strict
-- One handler per block type in Schema/Blocks.luau. Handlers receive already
-- validated fields. Handlers may yield; the Executor enforces a hard deadline.
--
-- ctx fields:
--   caster: Model, root: BasePart, ownerKey: string,
--   target: Model?          -- set inside onHit slots and Counter/ComboFinisher
--   shared: { anyHit: boolean, stopped: boolean, deadline: number }
--   runBlocks: (ctx, blocks) -> ()   -- provided by the Executor for slots
--   charge: number            -- 0..1 for Charge moves, 1 otherwise
--   vars / fighterVars        -- move-scope and fighter-scope variables
--   domain: Domain?           -- set inside a Domain's onTick
--   burnout: (seconds) -> ()  -- put every move on cooldown

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Config = require(Shared.Config)
local AnimationLibrary = require(Shared.AnimationLibrary)

local CombatService = require(script.Parent.Parent.CombatService)
local VfxService = require(script.Parent.Parent.VfxService)
local DomainService = require(script.Parent.Parent.DomainService)

local Actions: { [string]: (ctx: any, block: any) -> () } = {}

local function vec(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

local function alive(ctx: any): boolean
	return not ctx.shared.stopped and os.clock() < ctx.shared.deadline and CombatService.isAlive(ctx.caster)
end

-- Waits that stop early if the move gets cancelled.
local function sleep(ctx: any, seconds: number)
	local t = 0
	while t < seconds and alive(ctx) do
		t += task.wait(math.min(0.05, seconds - t))
	end
end

local function isFighterPart(part: Instance): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function chargeScale(ctx: any, enabled: boolean): number
	if not enabled then
		return 1
	end
	local min = Config.Charge.MinScale
	return min + (1 - min) * (ctx.charge or 1)
end

local function varTable(ctx: any, scope: string): { [string]: number }
	return if scope == "Fighter" then ctx.fighterVars else ctx.vars
end

local function childCtx(ctx: any, target: Model): any
	local c = table.clone(ctx)
	c.target = target
	return c
end

local function runOnHit(ctx: any, block: any, target: Model)
	ctx.shared.anyHit = true
	local slot = block.children and block.children.onHit
	if slot and #slot > 0 then
		-- each target gets its own thread so Waits don't delay other targets
		task.spawn(ctx.runBlocks, childCtx(ctx, target), slot)
	end
end

local function directionVector(root: BasePart, dir: string): Vector3
	local cf = root.CFrame
	if dir == "Forward" then
		return cf.LookVector
	elseif dir == "Backward" then
		return -cf.LookVector
	elseif dir == "Left" then
		return -cf.RightVector
	elseif dir == "Right" then
		return cf.RightVector
	elseif dir == "Up" then
		return Vector3.yAxis
	elseif dir == "Down" then
		return -Vector3.yAxis
	end
	return cf.LookVector
end

-- ── Flow ─────────────────────────────────────────────────────────────────
-- Repeat / If / Stop / Wait are handled here too so the Executor stays tiny.

Actions.Wait = function(ctx, block)
	sleep(ctx, block.fields.seconds)
end

Actions.Repeat = function(ctx, block)
	for _ = 1, block.fields.count do
		if not alive(ctx) then
			return
		end
		ctx.runBlocks(ctx, block.children.body)
	end
end

Actions.If = function(ctx, block)
	local f = block.fields
	local cond = false
	local state = CombatService.getState(ctx.caster)
	local humanoid = CombatService.humanoid(ctx.caster)
	if f.condition == "AnyTargetHit" then
		cond = ctx.shared.anyHit
	elseif f.condition == "HealthBelow" then
		cond = humanoid ~= nil and humanoid.Health / humanoid.MaxHealth * 100 < f.value
	elseif f.condition == "EnergyAbove" then
		cond = state ~= nil and state.energy > f.value
	elseif f.condition == "Chance" then
		cond = math.random() * 100 < f.value
	elseif f.condition == "Airborne" then
		cond = humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air
	elseif f.condition == "TargetBlocking" then
		local ts = ctx.target and CombatService.getState(ctx.target)
		cond = ts ~= nil and ts.blocking
	elseif f.condition == "ChargeAbove" then
		cond = (ctx.charge or 1) * 100 > f.value
	elseif f.condition == "VarAbove" then
		-- move-scope first, then fighter-scope
		local v = ctx.vars[f.var]
		if v == nil then
			v = ctx.fighterVars[f.var]
		end
		cond = (v or 0) > f.value
	elseif f.condition == "InOwnDomain" then
		local d = DomainService.activeFor(ctx.caster)
		cond = d ~= nil and DomainService.isInside(ctx.caster, d)
	end
	ctx.runBlocks(ctx, if cond then block.children["then"] else block.children["else"])
end

Actions.Stop = function(ctx, _block)
	ctx.shared.stopped = true
end

Actions.Variable = function(ctx, block)
	local f = block.fields
	local vars = varTable(ctx, f.scope)
	local current = vars[f.var] or 0
	local value = if f.op == "Set" then f.value else current + f.value
	vars[f.var] = math.clamp(value, -1000, 1000)
end

-- ── Combat ───────────────────────────────────────────────────────────────

Actions.Hitbox = function(ctx, block)
	local f = block.fields
	local size = vec(f.size)
	local offset = CFrame.new(vec(f.offset))
	local hitSet: { [Model]: boolean } = {}
	local count = 0
	local elapsed = 0
	repeat
		local cf = ctx.root.CFrame * offset
		for _, model in CombatService.query(ctx.caster, cf, size, f.shape) do
			if not hitSet[model] and count < f.maxTargets then
				hitSet[model] = true
				count += 1
				runOnHit(ctx, block, model)
			end
		end
		if f.duration <= 0 or count >= f.maxTargets then
			break
		end
		elapsed += task.wait(1 / 30)
	until elapsed >= f.duration or not alive(ctx)
end

Actions.Projectile = function(ctx, block)
	local f = block.fields
	local origin = ctx.root.CFrame * CFrame.new(vec(f.offset))
	local direction = ctx.aim or ctx.root.CFrame.LookVector
	local cf = CFrame.lookAt(origin.Position, origin.Position + direction)

	-- Clients animate the projectile themselves from (origin, speed, range), so
	-- it looks smooth; the server only simulates hits.
	local projectileId = VfxService.projectile(ctx.ownerKey, f.vfx, cf, f.speed, f.range)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { ctx.caster }

	-- Runs in its own thread so the move continues while it flies.
	task.spawn(function()
		local travelled = 0
		local hitSet: { [Model]: boolean } = {}
		while travelled < f.range and not ctx.shared.stopped do
			local dt = RunService.Heartbeat:Wait()
			local step = math.min(f.speed * dt, f.range - travelled)
			local wall = workspace:Raycast(cf.Position, cf.LookVector * step, rayParams)
			if wall and not isFighterPart(wall.Instance) then
				cf = CFrame.lookAt(wall.Position, wall.Position + cf.LookVector)
				break -- hit terrain/wall
			end
			cf += cf.LookVector * step
			travelled += step
			local hits = CombatService.query(ctx.caster, cf, Vector3.one * f.radius * 2, "Sphere")
			local stop = false
			for _, model in hits do
				if not hitSet[model] then
					hitSet[model] = true
					runOnHit(ctx, block, model)
					if not f.pierce then
						stop = true
						break
					end
				end
			end
			if stop then
				break
			end
		end
		VfxService.projectileEnd(projectileId, cf.Position)
	end)
end

Actions.Damage = function(ctx, block)
	if not ctx.target then
		return
	end
	local f = block.fields
	local amount = f.amount * chargeScale(ctx, f.scaleWithCharge)
	if CombatService.hasArmor(ctx.target) and not f.ignoreArmor then
		amount *= 0.7
	end
	-- Sure-hit domains can't be blocked.
	local sureHit = ctx.domain ~= nil and ctx.domain.sureHit
	CombatService.damage(ctx.caster, ctx.target, amount, { guardBreak = f.guardBreak, unblockable = sureHit })
end

Actions.Knockback = function(ctx, block)
	if ctx.target then
		local f = block.fields
		CombatService.knockback(ctx.caster, ctx.target, f.direction, f.force * chargeScale(ctx, f.scaleWithCharge))
	end
end

Actions.Stun = function(ctx, block)
	if ctx.target then
		CombatService.stun(ctx.target, block.fields.seconds)
	end
end

Actions.Grab = function(ctx, block)
	local target = ctx.target
	local tr = target and CombatService.root(target)
	if not target or not tr or CombatService.hasArmor(target) then
		return
	end
	local f = block.fields
	CombatService.stun(target, f.seconds)
	local offset = CFrame.new(vec(f.offset)) * CFrame.Angles(0, math.pi, 0)
	local align = Instance.new("AlignPosition")
	local a0 = Instance.new("Attachment")
	a0.Parent = tr
	align.Attachment0 = a0
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.MaxForce = math.huge
	align.Responsiveness = 200
	align.Parent = tr
	local t = 0
	while t < f.seconds and alive(ctx) and CombatService.isAlive(target) do
		align.Position = (ctx.root.CFrame * offset).Position
		t += task.wait()
	end
	align:Destroy()
	a0:Destroy()
end

-- ── Movement ─────────────────────────────────────────────────────────────

Actions.Dash = function(ctx, block)
	local f = block.fields
	if f.distance <= 0 then
		return
	end
	local dir = directionVector(ctx.root, f.direction)
	CombatService.push(ctx.root, dir * (f.distance / f.seconds), f.seconds)
	sleep(ctx, f.seconds)
end

Actions.FaceTarget = function(ctx, block)
	local target = CombatService.nearest(ctx.caster, block.fields.range)
	local tr = target and CombatService.root(target)
	if tr then
		local pos = ctx.root.Position
		local look = Vector3.new(tr.Position.X, pos.Y, tr.Position.Z)
		if (look - pos).Magnitude > 0.05 then
			ctx.root.CFrame = CFrame.lookAt(pos, look)
		end
		ctx.aim = (tr.Position - pos).Unit
	end
end

Actions.Teleport = function(ctx, block)
	local f = block.fields
	local destination: CFrame
	local tr = ctx.target and CombatService.root(ctx.target)
	if f.mode == "BehindTarget" and tr then
		destination = tr.CFrame * CFrame.new(0, 0, 3)
	else
		destination = ctx.root.CFrame * CFrame.new(0, 0, -f.distance)
	end
	-- don't teleport through walls
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ctx.caster }
	local delta = destination.Position - ctx.root.Position
	if delta.Magnitude > 0.05 then
		local hit = workspace:Raycast(ctx.root.Position, delta, params)
		if hit and not isFighterPart(hit.Instance) then
			destination = CFrame.new(hit.Position - delta.Unit * 2) * destination.Rotation
		end
	end
	ctx.caster:PivotTo(destination * ctx.root.CFrame:ToObjectSpace(ctx.caster:GetPivot()))
end

-- ── Self ─────────────────────────────────────────────────────────────────

Actions.CostEnergy = function(ctx, block)
	if not CombatService.spendEnergy(ctx.caster, block.fields.amount) then
		ctx.shared.stopped = true
		local player = Players:GetPlayerFromCharacter(ctx.caster)
		if player then
			Remotes.event("Notify"):FireClient(player, "Not enough cursed energy!", "warn")
		end
	end
end

Actions.Heal = function(ctx, block)
	CombatService.heal(ctx.caster, block.fields.amount)
end

Actions.Armor = function(ctx, block)
	CombatService.setArmor(ctx.caster, block.fields.seconds)
end

Actions.SpeedBoost = function(ctx, block)
	local key = {}
	CombatService.setSpeedMod(ctx.caster, key, block.fields.multiplier)
	task.delay(block.fields.seconds, function()
		CombatService.setSpeedMod(ctx.caster, key, nil)
	end)
end

-- ── Visual / Audio ───────────────────────────────────────────────────────

local animCache: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any

Actions.PlayAnimation = function(ctx, block)
	local f = block.fields
	local preset = f.preset ~= "" and AnimationLibrary.ByKey[f.preset]
	local animationId = if preset then preset.id else f.animationId
	if animationId == "" then
		return
	end
	local humanoid = ctx.caster:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local cache = animCache[animator]
	if not cache then
		cache = {}
		animCache[animator] = cache
	end
	local track = cache[animationId]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. animationId
		local ok, loaded = pcall(animator.LoadAnimation, animator, anim)
		if not ok then
			return
		end
		track = loaded
		track.Priority = Enum.AnimationPriority.Action
		cache[animationId] = track
	end
	if f.stopPrevious then
		for _, t in animator:GetPlayingAnimationTracks() do
			if t ~= track and t.Priority == Enum.AnimationPriority.Action then
				t:Stop(0.1)
			end
		end
	end
	track:Play(0.1, 1, f.speed)
end

Actions.PlayVfx = function(ctx, block)
	local f = block.fields
	if f.vfx == "" then
		return
	end
	local offset = CFrame.new(vec(f.offset))
	if f.at == "Target" then
		local tr = ctx.target and CombatService.root(ctx.target)
		if tr then
			VfxService.play(ctx.ownerKey, f.vfx, { part = tr, offset = offset, lifetime = f.seconds })
		end
	elseif f.at == "InFront" then
		VfxService.play(ctx.ownerKey, f.vfx, { cframe = ctx.root.CFrame * CFrame.new(0, 0, -4), offset = offset, lifetime = f.seconds })
	else
		VfxService.play(ctx.ownerKey, f.vfx, { part = ctx.root, offset = offset, lifetime = f.seconds })
	end
end

Actions.PlaySound = function(ctx, block)
	local f = block.fields
	if f.soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. f.soundId
	sound.Volume = f.volume
	sound.PlaybackSpeed = f.pitch
	sound.RollOffMaxDistance = 120
	sound.Parent = ctx.root
	sound:Play()
	Debris:AddItem(sound, 10)
end

Actions.CameraShake = function(ctx, block)
	local f = block.fields
	local shake = Remotes.event("CameraShake")
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local r = character and CombatService.root(character)
		if r and (r.Position - ctx.root.Position).Magnitude <= f.radius then
			shake:FireClient(player, f.intensity, f.seconds)
		end
	end
end

-- ── Domain ───────────────────────────────────────────────────────────────

Actions.Domain = function(ctx, block)
	local f = block.fields
	local color = Color3.fromRGB(f.color[1], f.color[2], f.color[3])
	local domain, err = DomainService.open(ctx.caster, f.radius, f.refinement, f.trap, color)
	local player = Players:GetPlayerFromCharacter(ctx.caster)
	if not domain then
		if player and err == "clash_lost" then
			Remotes.event("Notify"):FireClient(player, "Your domain was overpowered!", "warn")
		end
		ctx.burnout(f.burnout * 0.5)
		return
	end
	domain.sureHit = f.sureHit
	if f.vfx ~= "" then
		VfxService.play(ctx.ownerKey, f.vfx, { cframe = CFrame.new(domain.center), lifetime = math.min(f.seconds, 6) })
	end

	-- The domain lives in the background with its own deadline, so the move
	-- itself finishes and the caster can keep fighting inside it.
	local domainShared = { anyHit = false, stopped = false, deadline = os.clock() + f.seconds + 1 }
	local dctx = table.clone(ctx)
	dctx.shared = domainShared
	dctx.domain = domain
	dctx.ignoreStun = true -- the barrier holds even if the caster is stunned
	task.spawn(function()
		local endTime = os.clock() + f.seconds
		local slot = block.children and block.children.onTick or {}
		while os.clock() < endTime and not domain.closed and CombatService.isAlive(ctx.caster) do
			for _, model in domain.inside() do
				domainShared.anyHit = true
				local tctx = table.clone(dctx)
				tctx.target = model
				task.spawn(ctx.runBlocks, tctx, slot)
			end
			task.wait(f.tick)
		end
		domainShared.stopped = true
		domain.close("expired")
		ctx.burnout(f.burnout)
		if player then
			Remotes.event("Notify"):FireClient(player, `Burnout: technique unavailable for {f.burnout}s`, "warn")
		end
	end)
end

-- Sanity check: every schema block must have a handler.
local Blocks = require(Shared.Schema.Blocks)
for _, def in Blocks.List do
	assert(Actions[def.id], "missing action handler for block " .. def.id)
end

return Actions
