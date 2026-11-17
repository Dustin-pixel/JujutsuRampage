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

-- Camera shake --------------------------------------------------------------

local shakeIntensity = 0
local shakeUntil = 0

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
