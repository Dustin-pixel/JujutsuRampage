--!strict
-- The server never builds particles. It keeps track of which effects each
-- fighter's equipped moveset contains, sends that library to clients once
-- (MovesetChanged), and afterwards only sends tiny "play effect X" messages.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local VfxService = {}

local playVfx = Remotes.event("PlayVfx")
local movesetChanged = Remotes.event("MovesetChanged")

-- ownerKey -> { [effectId] = effect }
local libraries: { [string]: { [string]: any } } = {}

function VfxService.ownerKey(model: Model): string
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return "u" .. player.UserId
	end
	return "npc_" .. model:GetFullName()
end

-- Call when a fighter equips a moveset. `effects` must already be validated.
function VfxService.setLibrary(ownerKey: string, effects: { [string]: any })
	libraries[ownerKey] = effects
	movesetChanged:FireAllClients(ownerKey, effects)
end

function VfxService.clear(ownerKey: string)
	libraries[ownerKey] = nil
	movesetChanged:FireAllClients(ownerKey, nil)
end

function VfxService.has(ownerKey: string, effectId: string): boolean
	local lib = libraries[ownerKey]
	return lib ~= nil and lib[effectId] ~= nil
end

export type Attach = {
	part: BasePart?,
	cframe: CFrame?,
	offset: CFrame?,
	lifetime: number?,
}

function VfxService.play(ownerKey: string, effectId: string, attach: Attach)
	if effectId == "" or not VfxService.has(ownerKey, effectId) then
		return
	end
	playVfx:FireAllClients(ownerKey, effectId, attach)
end

-- Projectiles: clients animate them locally from origin/speed/range (smooth,
-- no per-frame replication). The server tells them when it stopped early.
local projectileEvent = Remotes.event("Projectile")
local projectileEndEvent = Remotes.event("ProjectileEnd")
local nextProjectileId = 0

function VfxService.projectile(ownerKey: string, effectId: string, origin: CFrame, speed: number, range: number): number
	nextProjectileId += 1
	local id = nextProjectileId
	if effectId ~= "" and VfxService.has(ownerKey, effectId) then
		projectileEvent:FireAllClients(id, ownerKey, effectId, origin, speed, range)
	end
	return id
end

function VfxService.projectileEnd(id: number, position: Vector3)
	projectileEndEvent:FireAllClients(id, position)
end

-- Late joiners get every library that is currently equipped.
Players.PlayerAdded:Connect(function(player)
	for key, lib in libraries do
		movesetChanged:FireClient(player, key, lib)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	VfxService.clear("u" .. player.UserId)
end)

return VfxService
