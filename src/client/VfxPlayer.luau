--!strict
-- Receives effect libraries (MovesetChanged) and play requests (PlayVfx) from
-- the server and builds the particles locally. Also handles camera shake.
-- Libraries arriving here were validated by the server, but they are
-- re-validated anyway since this is cheap and keeps the client robust.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local VfxBuilder = require(Shared.Vfx.VfxBuilder)
local VfxValidator = require(Shared.Validate.VfxValidator)

local VfxPlayer = {}

local libraries: { [string]: { [string]: any } } = {}
local shakeIntensity = 0
local shakeUntil = 0

Remotes.event("MovesetChanged").OnClientEvent:Connect(function(ownerKey: string, effects: any)
	if effects == nil then
		libraries[ownerKey] = nil
	else
		libraries[ownerKey] = VfxValidator.library(effects)
	end
end)

Remotes.event("PlayVfx").OnClientEvent:Connect(function(ownerKey: string, effectId: string, attach: any)
	local lib = libraries[ownerKey]
	local effect = lib and lib[effectId]
	if not effect or type(attach) ~= "table" then
		return
	end
	local part = if typeof(attach.part) == "Instance" and attach.part:IsA("BasePart") then attach.part else nil
	local cframe = if typeof(attach.cframe) == "CFrame" then attach.cframe else nil
	if not part and not cframe then
		return
	end
	VfxBuilder.play(effect, {
		part = part,
		cframe = cframe,
		offset = if typeof(attach.offset) == "CFrame" then attach.offset else nil,
		lifetime = if type(attach.lifetime) == "number" then attach.lifetime else nil,
	})
end)

-- Projectiles -------------------------------------------------------------------
-- Animated locally from origin/speed/range so they look smooth; the server
-- sends ProjectileEnd when it hit something or a wall.

local projectiles: { [number]: { part: BasePart, handle: any, stopped: boolean } } = {}

Remotes.event("Projectile").OnClientEvent:Connect(function(id: number, ownerKey: string, effectId: string, origin: CFrame, speed: number, range: number)
	local lib = libraries[ownerKey]
	local effect = lib and lib[effectId]
	if not effect or typeof(origin) ~= "CFrame" or type(speed) ~= "number" or type(range) ~= "number" then
		return
	end
	local part = Instance.new("Part")
	part.Name = "ProjectileVisual"
	part.Size = Vector3.one * 0.2
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = origin
	part.Parent = workspace
	local lifetime = math.clamp(range / math.max(speed, 1), 0.1, 6)
	local handle = VfxBuilder.play(effect, { part = part, lifetime = lifetime })
	local entry = { part = part, handle = handle, stopped = false }
	projectiles[id] = entry
	local travelled = 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		if entry.stopped or travelled >= range then
			conn:Disconnect()
			return
		end
		local step = math.min(speed * dt, range - travelled)
		travelled += step
		part.CFrame += part.CFrame.LookVector * step
	end)
	task.delay(lifetime + 3, function()
		projectiles[id] = nil
		part:Destroy()
	end)
end)

Remotes.event("ProjectileEnd").OnClientEvent:Connect(function(id: number, position: Vector3)
	local entry = projectiles[id]
	if not entry then
		return
	end
	entry.stopped = true
	if typeof(position) == "Vector3" then
		entry.part.CFrame = CFrame.new(position) * entry.part.CFrame.Rotation
	end
	-- stop emitting; let particles fade
	for _, d in entry.part:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
		end
	end
	task.delay(0.15, function()
		for _, d in entry.part:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = 1
			end
		end
	end)
end)

-- Domain screen effect -------------------------------------------------------------

local Lighting = game:GetService("Lighting")
local domainTint: ColorCorrectionEffect? = nil

Remotes.event("Domain").OnClientEvent:Connect(function(phase: string, info: any)
	if phase == "open" and type(info) == "table" and typeof(info.color) == "Color3" then
		if domainTint then
			domainTint:Destroy()
		end
		local tint = Instance.new("ColorCorrectionEffect")
		tint.Name = "DomainTint"
		tint.TintColor = Color3.new(1, 1, 1):Lerp(info.color, 0.35)
		tint.Contrast = 0.15
		tint.Saturation = -0.2
		tint.Parent = Lighting
		domainTint = tint
		task.delay(12, function() -- fallback if we never receive "close" (walked away)
			if domainTint == tint then
				tint:Destroy()
				domainTint = nil
			end
		end)
		shakeIntensity, shakeUntil = 1, os.clock() + 0.5
	elseif phase == "close" then
		if domainTint then
			domainTint:Destroy()
			domainTint = nil
		end
	elseif phase == "clash" then
		shakeIntensity, shakeUntil = 1.5, os.clock() + 0.8
	end
end)

-- Camera shake --------------------------------------------------------------


Remotes.event("CameraShake").OnClientEvent:Connect(function(intensity: number, seconds: number)
	shakeIntensity = math.max(shakeIntensity, math.clamp(intensity, 0, 2))
	shakeUntil = math.max(shakeUntil, os.clock() + math.clamp(seconds, 0, 2))
end)

RunService:BindToRenderStep("JJRCameraShake", Enum.RenderPriority.Camera.Value + 1, function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local remaining = shakeUntil - os.clock()
	if remaining <= 0 then
		shakeIntensity = 0
		return
	end
	local m = shakeIntensity * math.min(1, remaining * 4)
	camera.CFrame *= CFrame.Angles(
		math.rad((math.random() - 0.5) * 2 * m),
		math.rad((math.random() - 0.5) * 2 * m),
		0
	) + Vector3.new((math.random() - 0.5) * m * 0.3, (math.random() - 0.5) * m * 0.3, 0)
end)

return VfxPlayer
