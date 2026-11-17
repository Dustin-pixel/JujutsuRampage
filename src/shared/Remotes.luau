--!strict
-- All network traffic in one place. The server creates the instances; clients
-- wait for them. Every server handler must treat its arguments as untrusted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"UseMove", -- C->S (slot: number, aimDirection: Vector3?, phase: "down" | "up")
	"M1", -- C->S
	"Block", -- C->S (holding: boolean)
	"PlayVfx", -- S->C (ownerUserId, effectId, attach info)
	"CameraShake", -- S->C (intensity, seconds)
	"Notify", -- S->C (text, kind)
	"CombatState", -- S->C (state table for HUD)
	"Cooldown", -- S->C (slot, seconds)
	"MovesetChanged", -- S->C (userId, equipped moveset) so clients can cache effects
	"Projectile", -- S->C (id, ownerKey, effectId, origin: CFrame, speed, range) clients animate it locally
	"ProjectileEnd", -- S->C (id, position) server says it hit something / stopped
	"Domain", -- S->C (phase "open"|"close"|"clash", info) for screen effects
}

local FUNCTIONS = {
	"GetProfile", -- C->S -> { slots, equipped, vfxLibrary }
	"SaveMoveset", -- C->S (slotIndex, moveset) -> result
	"DeleteMoveset", -- C->S (slotIndex)
	"EquipMoveset", -- C->S (slotIndex) -> ok, err
	"ImportCode", -- C->S (code) -> { kind, value, warnings } | { error }
	"ExportCode", -- C->S (kind, slotIndex | effectId) -> code | nil, err
	"SaveVfx", -- C->S (effectId?, effect) -> id | nil, err
	"DeleteVfx", -- C->S (effectId)
	"GalleryList", -- C->S (sort "recent"|"top", page) -> { entries, hasMore }
	"GalleryPublish", -- C->S (slotIndex, description) -> ok, err
	"GalleryUnpublish", -- C->S (entryId) -> ok
	"GalleryLike", -- C->S (entryId) -> ok, likes
	"GalleryReport", -- C->S (entryId) -> ok
	"GalleryImport", -- C->S (entryId) -> import result
	"GalleryMine", -- C->S () -> { entries }
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, name in EVENTS do
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = folder
		end
		for _, name in FUNCTIONS do
			local f = Instance.new("RemoteFunction")
			f.Name = name
			f.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), "unknown remote event " .. name)
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	assert(table.find(FUNCTIONS, name), "unknown remote function " .. name)
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
